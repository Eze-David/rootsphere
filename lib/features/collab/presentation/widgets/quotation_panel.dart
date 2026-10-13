import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/services/quotation_pdf_service.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/research_quotation.dart';
import '../providers/opportunity_providers.dart';
import 'opportunity_actions.dart' show currentOpportunityUserId;
import '../providers/quotation_providers.dart';
import '../providers/role_verification_providers.dart';
import 'send_quotation_sheet.dart';

/// The quotation step of a research request, shown in its detail sheet.
/// Requester: see the quotation, accept & pay or decline. Admin: send or
/// revise it. Nobody else ever sees it (quotations are RLS-limited to those
/// two, and held requests aren't visible to anyone else at all).
class QuotationPanel extends ConsumerWidget {
  const QuotationPanel({super.key, required this.opportunity});

  final CollaborationOpportunity opportunity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The detail sheet is opened with a snapshot; read the live row so the
    // panel follows accept/decline/payment as they happen (realtime).
    final CollaborationOpportunity opportunity =
        (ref.watch(opportunitiesProvider).value ??
                const <CollaborationOpportunity>[])
            .where((o) => o.id == this.opportunity.id)
            .firstOrNull ??
        this.opportunity;
    final QuoteState? state = opportunity.quoteState;
    if (state == null) return const SizedBox.shrink();
    final bool isRequester =
        opportunity.requesterId == currentOpportunityUserId();
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;
    if (!isRequester && !isAdmin) return const SizedBox.shrink();

    final ResearchQuotation? quote = ref.watch(
      currentQuotationProvider(opportunity.id),
    );
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color muted = theme.colorScheme.onSurfaceVariant;

    final List<Widget> children = <Widget>[
      Row(
        children: <Widget>[
          Icon(
            Icons.request_quote_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'QUOTATION',
              style: text.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _QuoteStateChip(state: state),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
    ];

    if (state == QuoteState.awaitingQuote || quote == null) {
      children.add(
        Text(
          isRequester
              ? "Thank you — RootSphere is reviewing your request. You'll be "
                    'notified as soon as your quotation is ready. Your request '
                    'goes to researchers once the quotation is accepted and '
                    'paid.'
              : 'Review the request form, then send the requester an '
                    'itemised quotation.',
          style: text.bodySmall?.copyWith(color: muted),
        ),
      );
    } else {
      children.add(QuotationDetails(quotation: quote));
      children.add(const SizedBox(height: AppSpacing.sm));
      children.addAll(
        _statusMessage(context, state, quote, isRequester, text, muted),
      );
    }

    final List<Widget> actions = <Widget>[
      if (isRequester && quote != null)
        ..._requesterActions(context, ref, state, quote),
      if (isAdmin &&
          (state == QuoteState.awaitingQuote ||
              state == QuoteState.quoted ||
              state == QuoteState.declined))
        FilledButton.tonalIcon(
          onPressed: () => showSendQuotationSheet(
            context,
            opportunity: opportunity,
            previous: quote,
          ),
          icon: Icon(quote == null ? Icons.send_outlined : Icons.edit_outlined),
          label: Text(quote == null ? 'Prepare quotation' : 'Revise quotation'),
        ),
      if (quote != null)
        _PrintQuotationButton(opportunity: opportunity, quotation: quote),
    ];
    if (actions.isNotEmpty) {
      children.add(const SizedBox(height: AppSpacing.md));
      children.add(
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: actions,
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  List<Widget> _statusMessage(
    BuildContext context,
    QuoteState state,
    ResearchQuotation quote,
    bool isRequester,
    TextTheme text,
    Color muted,
  ) {
    String? message;
    switch (state) {
      case QuoteState.quoted:
        if (quote.isExpired) {
          message = isRequester
              ? 'This quotation has expired. Contact RootSphere for a new one.'
              : 'This quotation has expired — send a revised one.';
        } else if (!isRequester) {
          message = 'Waiting for the requester to accept or decline.';
        }
      case QuoteState.accepted:
        message = isRequester
            ? 'You accepted this quotation. Complete payment to send your '
                  'request to researchers.'
            : 'Accepted — waiting for payment.';
      case QuoteState.declined:
        message = isRequester
            ? 'You declined this quotation. RootSphere may send you a '
                  'revised one.'
            : 'Declined${(quote.declineReason ?? '').isEmpty ? '' : ': "${quote.declineReason}"'}.';
      case QuoteState.paid:
        message =
            'Paid${quote.paidAt == null ? '' : ' on ${MaterialLocalizations.of(context).formatMediumDate(quote.paidAt!)}'}'
            ' — the request is now with researchers.';
      case QuoteState.awaitingQuote:
        break;
    }
    if (message == null) return const <Widget>[];
    return <Widget>[
      Text(message, style: text.bodySmall?.copyWith(color: muted)),
    ];
  }

  List<Widget> _requesterActions(
    BuildContext context,
    WidgetRef ref,
    QuoteState state,
    ResearchQuotation quote,
  ) {
    if (state == QuoteState.quoted &&
        quote.status == QuotationStatus.sent &&
        !quote.isExpired) {
      return <Widget>[
        FilledButton.icon(
          onPressed: () => _acceptAndPay(context, ref, quote),
          icon: const Icon(Icons.check_circle_outline),
          label: Text('Accept & pay ${formatNaira(quote.totalCents)}'),
        ),
        OutlinedButton(
          onPressed: () => _decline(context, ref, quote),
          child: const Text('Decline'),
        ),
      ];
    }
    if (state == QuoteState.accepted &&
        quote.status == QuotationStatus.accepted) {
      return <Widget>[
        FilledButton.icon(
          onPressed: () => _pay(context, ref, quote),
          icon: const Icon(Icons.payment_outlined),
          label: Text('Pay ${formatNaira(quote.totalCents)}'),
        ),
      ];
    }
    return const <Widget>[];
  }

  Future<void> _acceptAndPay(
    BuildContext context,
    WidgetRef ref,
    ResearchQuotation quote,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept quotation?'),
        content: Text(
          'You are accepting quotation ${quote.reference} for '
          '${formatNaira(quote.totalCents)}. You will then be taken to '
          'Paystack to pay securely. Research begins once payment is '
          'confirmed.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept & pay'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(quotationServiceProvider).respond(quote.id, accept: true);
    } catch (e) {
      if (context.mounted) _snack(context, friendlyErrorMessage(e));
      return;
    }
    if (context.mounted) await _pay(context, ref, quote);
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    ResearchQuotation quote,
  ) async {
    _snack(context, 'Opening secure checkout…');
    try {
      final String url = await ref
          .read(quotationServiceProvider)
          .startPayment(quote.id);
      // Same tab on web (after an await the browser would block a popup);
      // Paystack's callback brings the user back to this request.
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } catch (e) {
      if (context.mounted) _snack(context, friendlyErrorMessage(e));
    }
  }

  Future<void> _decline(
    BuildContext context,
    WidgetRef ref,
    ResearchQuotation quote,
  ) async {
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline quotation?'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'e.g. above my budget, timeframe too long…',
            alignLabelWithHint: true,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    final String text = reason.text.trim();
    reason.dispose();
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(quotationServiceProvider)
          .respond(quote.id, accept: false, reason: text);
      if (context.mounted) _snack(context, 'Quotation declined.');
    } catch (e) {
      if (context.mounted) _snack(context, friendlyErrorMessage(e));
    }
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Itemised table + total + timeframe/validity/notes.
class QuotationDetails extends StatelessWidget {
  const QuotationDetails({super.key, required this.quotation});

  final ResearchQuotation quotation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final MaterialLocalizations l = MaterialLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${quotation.reference} · issued ${l.formatMediumDate(quotation.createdAt)}',
          style: text.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final QuoteLineItem item in quotation.lineItems)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: Text(item.description, style: text.bodyMedium)),
                const SizedBox(width: AppSpacing.md),
                Text(formatNaira(item.amountCents), style: text.bodyMedium),
              ],
            ),
          ),
        const Divider(),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Total',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              formatNaira(quotation.totalCents),
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        if (quotation.timeframe.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text('Estimated timeframe', style: text.labelSmall),
          Text(quotation.timeframe, style: text.bodyMedium),
        ],
        if (quotation.validUntil != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text('Valid until', style: text.labelSmall),
          Text(
            l.formatMediumDate(quotation.validUntil!),
            style: text.bodyMedium?.copyWith(
              color: quotation.isExpired ? theme.colorScheme.error : null,
            ),
          ),
        ],
        if (quotation.notes.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text('Notes & terms', style: text.labelSmall),
          Text(quotation.notes, style: text.bodyMedium),
        ],
      ],
    );
  }
}

class _QuoteStateChip extends StatelessWidget {
  const _QuoteStateChip({required this.state});
  final QuoteState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool done = state == QuoteState.paid;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: done ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Text(
        state.label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: done ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PrintQuotationButton extends StatefulWidget {
  const _PrintQuotationButton({
    required this.opportunity,
    required this.quotation,
  });

  final CollaborationOpportunity opportunity;
  final ResearchQuotation quotation;

  @override
  State<_PrintQuotationButton> createState() => _PrintQuotationButtonState();
}

class _PrintQuotationButtonState extends State<_PrintQuotationButton> {
  bool _busy = false;

  Future<void> _print() async {
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(
        format: PdfPageFormat.a4,
        name: 'Quotation ${widget.quotation.reference}.pdf',
        onLayout: (PdfPageFormat format) => QuotationPdfService.build(
          opportunity: widget.opportunity,
          quotation: widget.quotation,
          format: format,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not prepare the quotation. Check your internet '
              'connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _print,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.print_outlined, size: 18),
      label: const Text('Print quotation'),
    );
  }
}
