import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../data/services/research_request_pdf_service.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../../domain/entities/research_request.dart';
import '../providers/opportunity_providers.dart';

/// "Print form" for a submitted research request. Only renders once the
/// form has loaded — opportunity_subjects' RLS limits that to the requester,
/// the claimer and platform admins, so nobody else ever sees the button.
class PrintResearchRequestButton extends ConsumerStatefulWidget {
  const PrintResearchRequestButton({super.key, required this.opportunity});

  final CollaborationOpportunity opportunity;

  @override
  ConsumerState<PrintResearchRequestButton> createState() =>
      _PrintResearchRequestButtonState();
}

class _PrintResearchRequestButtonState
    extends ConsumerState<PrintResearchRequestButton> {
  bool _busy = false;

  Future<void> _print(OpportunitySubject subject) async {
    setState(() => _busy = true);
    try {
      final bool launched = await Printing.layoutPdf(
        format: PdfPageFormat.a4,
        name:
            'Research Request ${researchReferenceNumber(widget.opportunity.id)}.pdf',
        onLayout: (PdfPageFormat format) => ResearchRequestPdfService.build(
          opportunity: widget.opportunity,
          subject: subject,
          format: format,
        ),
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printing was cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not prepare the form. Check your internet connection '
              'and try again.',
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
    final OpportunitySubject? subject = ref
        .watch(opportunitySubjectProvider(widget.opportunity.id))
        .value;
    if (subject == null || subject.isEmpty) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: _busy ? null : () => _print(subject),
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.print_outlined, size: 18),
      label: const Text('Print form'),
    );
  }
}
