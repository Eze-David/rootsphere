import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/research_quotation.dart';
import '../../domain/entities/research_request.dart';
import '../providers/quotation_providers.dart';
import 'print_research_request_button.dart';

/// Admin: compose (or revise) an itemised quotation for a research request.
/// [previous] pre-fills the form when revising.
Future<void> showSendQuotationSheet(
  BuildContext context, {
  required CollaborationOpportunity opportunity,
  ResearchQuotation? previous,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) =>
        _SendQuotationSheet(opportunity: opportunity, previous: previous),
  );
}

class _LineDraft {
  _LineDraft([String description = '', String amount = ''])
    : description = TextEditingController(text: description),
      amount = TextEditingController(text: amount);

  final TextEditingController description;
  final TextEditingController amount;

  /// Naira typed by the admin → kobo; null if blank/invalid.
  int? get amountCents {
    final double? naira = double.tryParse(
      amount.text.replaceAll(',', '').trim(),
    );
    if (naira == null || naira <= 0) return null;
    return (naira * 100).round();
  }

  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

class _SendQuotationSheet extends ConsumerStatefulWidget {
  const _SendQuotationSheet({required this.opportunity, this.previous});

  final CollaborationOpportunity opportunity;
  final ResearchQuotation? previous;

  @override
  ConsumerState<_SendQuotationSheet> createState() =>
      _SendQuotationSheetState();
}

class _SendQuotationSheetState extends ConsumerState<_SendQuotationSheet> {
  final List<_LineDraft> _lines = <_LineDraft>[];
  final TextEditingController _timeframe = TextEditingController();
  final TextEditingController _notes = TextEditingController();
  DateTime? _validUntil;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final ResearchQuotation? p = widget.previous;
    if (p != null) {
      for (final QuoteLineItem item in p.lineItems) {
        _lines.add(
          _LineDraft(
            item.description,
            (item.amountCents / 100).toStringAsFixed(
              item.amountCents % 100 == 0 ? 0 : 2,
            ),
          ),
        );
      }
      _timeframe.text = p.timeframe;
      _notes.text = p.notes;
    } else {
      _lines.add(_LineDraft());
    }
    _validUntil = DateTime.now().add(const Duration(days: 14));
    for (final _LineDraft l in _lines) {
      l.amount.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final _LineDraft l in _lines) {
      l.dispose();
    }
    _timeframe.dispose();
    _notes.dispose();
    super.dispose();
  }

  int get _totalCents => _lines.fold(0, (sum, l) => sum + (l.amountCents ?? 0));

  void _addLine() {
    final _LineDraft line = _LineDraft()..amount.addListener(_refresh);
    setState(() => _lines.add(line));
  }

  void _removeLine(_LineDraft line) {
    setState(() => _lines.remove(line));
    line.dispose();
  }

  Future<void> _pickValidUntil() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _validUntil ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _validUntil = picked);
  }

  Future<void> _send() async {
    final List<QuoteLineItem> items = <QuoteLineItem>[];
    for (final _LineDraft l in _lines) {
      final String d = l.description.text.trim();
      final int? cents = l.amountCents;
      if (d.isEmpty && l.amount.text.trim().isEmpty) continue;
      if (d.isEmpty || cents == null) {
        _snack('Every line needs a description and an amount above zero.');
        return;
      }
      items.add(QuoteLineItem(description: d, amountCents: cents));
    }
    if (items.isEmpty) {
      _snack('Add at least one line item.');
      return;
    }

    setState(() => _sending = true);
    try {
      await ref
          .read(quotationServiceProvider)
          .send(
            opportunityId: widget.opportunity.id,
            lineItems: items,
            timeframe: _timeframe.text.trim(),
            notes: _notes.text.trim(),
            validUntil: _validUntil,
          );
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Quotation sent to ${widget.opportunity.requesterName}.');
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        _snack(friendlyErrorMessage(e));
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.previous == null ? 'Send quotation' : 'Revise quotation',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${widget.opportunity.title} · '
              '${researchReferenceNumber(widget.opportunity.id)} · '
              'for ${widget.opportunity.requesterName}',
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrintResearchRequestButton(opportunity: widget.opportunity),
            const SizedBox(height: AppSpacing.lg),
            Text('LINE ITEMS', style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            for (int i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _lines[i].description,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: 'Item ${i + 1}',
                          hintText: 'e.g. Church records search',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _lines[i].amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '₦ ',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove line',
                      onPressed: _lines.length == 1
                          ? null
                          : () => _removeLine(_lines[i]),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('Add line'),
            ),
            const Divider(),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Total',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  formatNaira(_totalCents),
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _timeframe,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Estimated timeframe',
                hintText: 'e.g. 3–4 weeks from payment',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _pickValidUntil,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Valid until',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(
                  _validUntil == null
                      ? 'No expiry'
                      : MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_validUntil!),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notes,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notes & terms (optional)',
                hintText:
                    'What is included, travel costs, archive fees, '
                    'refund terms…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  'Send ${formatNaira(_totalCents)} quotation to '
                  '${widget.opportunity.requesterName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
