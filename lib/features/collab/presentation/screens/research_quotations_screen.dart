import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/research_request.dart';
import '../providers/opportunity_providers.dart';
import '../widgets/opportunity_actions.dart';

/// Admin queue for the quotation step: review new research requests, send
/// itemised quotations, and track acceptance and payment. Tapping a request
/// opens its detail sheet, where the quotation panel lives.
class ResearchQuotationsScreen extends ConsumerStatefulWidget {
  const ResearchQuotationsScreen({super.key, this.openOpportunityId});

  /// Opens this request's detail straight away (from a notification).
  final String? openOpportunityId;

  @override
  ConsumerState<ResearchQuotationsScreen> createState() =>
      _ResearchQuotationsScreenState();
}

class _ResearchQuotationsScreenState
    extends ConsumerState<ResearchQuotationsScreen> {
  bool _opened = false;

  static const List<(String, List<QuoteState>)> _tabs =
      <(String, List<QuoteState>)>[
        (
          'To quote',
          <QuoteState>[QuoteState.awaitingQuote, QuoteState.declined],
        ),
        ('Sent', <QuoteState>[QuoteState.quoted]),
        ('Awaiting payment', <QuoteState>[QuoteState.accepted]),
        ('Paid', <QuoteState>[QuoteState.paid]),
      ];

  void _maybeOpen(List<CollaborationOpportunity> all) {
    final String? id = widget.openOpportunityId;
    if (_opened || id == null) return;
    final CollaborationOpportunity? match = all
        .where((o) => o.id == id)
        .firstOrNull;
    if (match == null) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showOpportunityDetail(context, ref, match);
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<CollaborationOpportunity> all = ref.watch(quoteRequestsProvider);
    _maybeOpen(all);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Research quotations'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              for (final (String label, List<QuoteState> states) in _tabs)
                Tab(
                  text:
                      '$label (${all.where((o) => states.contains(o.quoteState)).length})',
                ),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            for (final (_, List<QuoteState> states) in _tabs)
              _QuoteList(
                items: all.where((o) => states.contains(o.quoteState)).toList()
                  ..sort(
                    (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
                      a.createdAt ?? DateTime(0),
                    ),
                  ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuoteList extends ConsumerWidget {
  const _QuoteList({required this.items});

  final List<CollaborationOpportunity> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.request_quote_outlined, size: 48, color: muted),
              const SizedBox(height: AppSpacing.md),
              Text('Nothing here', style: text.titleMedium),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final CollaborationOpportunity o = items[i];
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            title: Text(
              o.title,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${researchReferenceNumber(o.id)} · ${o.requesterName}'
              '${o.createdAt == null ? '' : ' · ${MaterialLocalizations.of(context).formatMediumDate(o.createdAt!.toLocal())}'}'
              '${o.quoteState == QuoteState.declined ? '\nDeclined — send a revised quotation' : ''}',
            ),
            isThreeLine: o.quoteState == QuoteState.declined,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showOpportunityDetail(context, ref, o),
          ),
        );
      },
    );
  }
}
