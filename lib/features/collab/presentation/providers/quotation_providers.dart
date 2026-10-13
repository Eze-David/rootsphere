import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/research_quotation.dart';

/// Every quotation for one request, newest first, kept live via realtime.
/// RLS limits these to the request's requester and admins.
final quotationsForOpportunityProvider = StreamProvider.autoDispose
    .family<List<ResearchQuotation>, String>((ref, opportunityId) {
      if (!SupabaseConfig.isReady) {
        return Stream<List<ResearchQuotation>>.value(
          const <ResearchQuotation>[],
        );
      }
      return SupabaseConfig.client
          .from('research_quotations')
          .stream(primaryKey: <String>['id'])
          .eq('opportunity_id', opportunityId)
          .order('created_at')
          .map(
            (rows) =>
                rows.map(ResearchQuotation.fromRow).toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          );
    });

/// The quotation that currently matters for a request — the newest one that
/// hasn't been replaced by a revision.
final currentQuotationProvider = Provider.autoDispose
    .family<ResearchQuotation?, String>((ref, opportunityId) {
      final List<ResearchQuotation> all =
          ref.watch(quotationsForOpportunityProvider(opportunityId)).value ??
          const <ResearchQuotation>[];
      for (final ResearchQuotation q in all) {
        if (q.status != QuotationStatus.superseded) return q;
      }
      return null;
    });

/// Thin wrapper over the quotation RPCs / edge function, turning database
/// error codes into plain-language [Failure]s.
class QuotationService {
  const QuotationService();

  SupabaseClient get _client => SupabaseConfig.client;

  Future<void> send({
    required String opportunityId,
    required List<QuoteLineItem> lineItems,
    required String timeframe,
    required String notes,
    DateTime? validUntil,
  }) async {
    await _rpc('send_research_quotation', <String, dynamic>{
      'p_opportunity_id': opportunityId,
      'p_line_items': lineItems.map((i) => i.toJson()).toList(),
      'p_timeframe': timeframe,
      'p_notes': notes,
      'p_valid_until': validUntil == null
          ? null
          : '${validUntil.year.toString().padLeft(4, '0')}-'
                '${validUntil.month.toString().padLeft(2, '0')}-'
                '${validUntil.day.toString().padLeft(2, '0')}',
    });
  }

  Future<void> respond(
    String quotationId, {
    required bool accept,
    String? reason,
  }) async {
    await _rpc('respond_research_quotation', <String, dynamic>{
      'p_quotation_id': quotationId,
      'p_accept': accept,
      'p_reason': reason,
    });
  }

  /// Starts Paystack checkout for an accepted quotation; returns the URL to
  /// open.
  Future<String> startPayment(String quotationId) async {
    try {
      final FunctionResponse res = await _client.functions.invoke(
        'create-quotation-payment',
        body: <String, dynamic>{'quotationId': quotationId},
      );
      final dynamic data = res.data;
      if (data is Map && data['available'] == true) {
        return data['authorizationUrl'].toString();
      }
      throw ServerFailure(
        data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Could not start payment.',
      );
    } on FunctionException catch (e) {
      final dynamic d = e.details;
      throw ServerFailure(
        d is Map && d['message'] != null
            ? d['message'].toString()
            : 'Payments are unavailable right now (${e.status}).',
      );
    }
  }

  Future<void> _rpc(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on PostgrestException catch (e) {
      throw ServerFailure(_friendly(e.message));
    }
  }

  static String _friendly(String raw) {
    if (raw.contains('quotation_expired')) {
      return 'This quotation has expired. Please contact RootSphere for a new one.';
    }
    if (raw.contains('quotation_not_open')) {
      return 'This quotation has already been answered.';
    }
    if (raw.contains('quotation_not_allowed')) {
      return 'A quotation can no longer be sent for this request.';
    }
    if (raw.contains('invalid_line_item') ||
        raw.contains('line_items_required')) {
      return 'Every line needs a description and an amount above zero.';
    }
    if (raw.contains('admin_only') || raw.contains('only_requester')) {
      return "You don't have permission to do that.";
    }
    return raw;
  }
}

final quotationServiceProvider = Provider<QuotationService>(
  (ref) => const QuotationService(),
);
