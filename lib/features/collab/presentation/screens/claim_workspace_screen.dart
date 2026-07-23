import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../../shared/widgets/fullscreen_document_text_viewer.dart';
import '../../../../shared/widgets/fullscreen_image_viewer.dart';
import '../../../../shared/widgets/fullscreen_pdf_viewer.dart';
import '../../domain/entities/finder_submission.dart';
import '../../domain/entities/indexer_submission.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/opportunity_subject.dart';
import '../providers/opportunity_providers.dart';

/// The workspace a claimer enters after claiming an opportunity.
///
/// It shows role-specific forms: Finder research forms or Indexer
/// transcription forms, and lets the claimer save progress or submit for
/// verification.
class ClaimWorkspaceScreen extends ConsumerStatefulWidget {
  const ClaimWorkspaceScreen({super.key, required this.opportunityId});

  final String opportunityId;

  @override
  ConsumerState<ClaimWorkspaceScreen> createState() =>
      _ClaimWorkspaceScreenState();
}

class _ClaimWorkspaceScreenState extends ConsumerState<ClaimWorkspaceScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(opportunitiesProvider);
    final opportunities = async.value ?? const <CollaborationOpportunity>[];
    final opportunity = opportunities
        .cast<CollaborationOpportunity?>()
        .firstWhere((o) => o?.id == widget.opportunityId, orElse: () => null);

    return Scaffold(
      appBar: AppBar(title: const Text('Claim workspace')),
      body: async.isLoading
          ? const Center(child: CircularProgressIndicator())
          : opportunity == null
          ? const Center(child: Text('Opportunity not found.'))
          : _WorkspaceBody(opportunity: opportunity),
    );
  }
}

class _WorkspaceBody extends ConsumerStatefulWidget {
  const _WorkspaceBody({required this.opportunity});
  final CollaborationOpportunity opportunity;

  @override
  ConsumerState<_WorkspaceBody> createState() => _WorkspaceBodyState();
}

class _WorkspaceBodyState extends ConsumerState<_WorkspaceBody> {
  late FinderSubmission _finderSubmission;
  late IndexerSubmission _indexerSubmission;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _finderSubmission =
        widget.opportunity.finderSubmission ?? const FinderSubmission();
    _indexerSubmission =
        widget.opportunity.indexerSubmission ?? const IndexerSubmission();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final opportunity = widget.opportunity;

    // Built once and handed to whichever form is showing, as the first
    // item(s) of its ListView — rather than living outside as fixed-size
    // Column siblings, which could overflow the screen once the subject
    // details section (photos, documents) grew past whatever the Expanded
    // form region had left.
    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _RoleBadge(role: opportunity.requiredRole),
        const SizedBox(height: AppSpacing.md),
        Text(
          opportunity.title,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          opportunity.requiredRole.description,
          style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SubjectDetailsSection(opportunityId: opportunity.id),
        if (!opportunity.isClaimed) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _WorkspaceStatusBanner(opportunity: opportunity),
        ] else if ((opportunity.companyFeedback ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          _RejectionFeedback(feedback: opportunity.companyFeedback!),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: opportunity.requiredRole == CollaborationRole.finder
              ? _FinderForm(
                  header: header,
                  submission: _finderSubmission,
                  onChanged: (s) => _finderSubmission = s,
                )
              : _IndexerForm(
                  header: header,
                  submission: _indexerSubmission,
                  onChanged: (s) => _indexerSubmission = s,
                ),
        ),
        if (opportunity.isClaimed)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save progress'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(
                  onPressed: _saving ? null : _submit,
                  child: const Text('Submit for verification'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final controller = ref.read(opportunityControllerProvider.notifier);
    try {
      if (widget.opportunity.requiredRole == CollaborationRole.finder) {
        await controller.saveFinderSubmission(
          widget.opportunity.id,
          _finderSubmission,
        );
      } else {
        await controller.saveIndexerSubmission(
          widget.opportunity.id,
          _indexerSubmission,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Progress saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    await _save();
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for verification'),
        content: const Text(
          'Are you ready to send this to the company for review? You can\'t '
          'edit it again until they respond.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(opportunityControllerProvider.notifier)
          .submitForReview(widget.opportunity.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted for company review.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// What's happening now for a submission that's past the editable
/// (`claimed`) stage — nothing left for the claimer to do but wait, except
/// after a rejection, which is shown separately via [_RejectionFeedback].
class _WorkspaceStatusBanner extends StatelessWidget {
  const _WorkspaceStatusBanner({required this.opportunity});
  final CollaborationOpportunity opportunity;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String message,
      Color bg,
    ) = switch (opportunity.status) {
      OpportunityStatus.submitted => (
        Icons.hourglass_top,
        'Awaiting company review.',
        AppColors.cream,
      ),
      OpportunityStatus.companyApproved => (
        Icons.check_circle_outline,
        "Approved by the company — waiting on the requester's final "
            'verification.',
        const Color(0xFFE8F5E9),
      ),
      OpportunityStatus.verified => (
        Icons.verified_outlined,
        'Verified — this opportunity is complete.',
        const Color(0xFFE8F5E9),
      ),
      OpportunityStatus.open ||
      OpportunityStatus.claimed => (Icons.info_outline, '', AppColors.cream),
    };
    if (message.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _RejectionFeedback extends StatelessWidget {
  const _RejectionFeedback({required this.feedback});
  final String feedback;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.sunGoldLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.feedback_outlined,
                size: 16,
                color: AppColors.sunGold,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('Changes requested by the company', style: text.labelSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(feedback),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final CollaborationRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.sunGoldLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(role.icon, size: 16, color: AppColors.sunGold),
          const SizedBox(width: AppSpacing.xs),
          Text(
            role.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.sunGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

const List<String> _imageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
];

String _extensionOf(String url) {
  final String path = Uri.tryParse(url)?.path ?? url;
  final int dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
}

Future<void> _openSubjectFile(BuildContext context, String url, String title) {
  final String ext = _extensionOf(url);
  if (_imageExtensions.contains(ext)) return showFullscreenImage(context, url);
  if (ext == 'pdf')
    return showFullscreenPdf(context, reference: url, title: title);
  return showFullscreenDocumentText(context, url: url, title: title);
}

/// Details about the person this opportunity is researching — only ever
/// reachable from here, the claim workspace, since [opportunitySubjectProvider]
/// is backed by RLS that restricts the row to the requester, the claimer,
/// and platform admins (see 20260722070000_opportunity_subjects.sql). Not
/// shown on the public board, the detail sheet, or the card.
class _SubjectDetailsSection extends ConsumerWidget {
  const _SubjectDetailsSection({required this.opportunityId});
  final String opportunityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<OpportunitySubject?> async = ref.watch(
      opportunitySubjectProvider(opportunityId),
    );
    final OpportunitySubject? subject = async.value;
    if (subject == null || subject.isEmpty) return const SizedBox.shrink();

    final TextTheme text = Theme.of(context).textTheme;
    // No outer padding here — this is embedded as a header item inside the
    // form's own ListView (see _WorkspaceBodyState.build), which already
    // pads every item uniformly. Wrapping it again doubled up the inset.
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        title: Text('SUBJECT DETAILS', style: text.labelSmall),
        children: <Widget>[
          if (subject.fullName.isNotEmpty)
            _SubjectField(label: 'Name', value: subject.fullName),
          if (subject.nickName.trim().isNotEmpty)
            _SubjectField(label: 'Nickname', value: subject.nickName),
          if (subject.country.trim().isNotEmpty)
            _SubjectField(label: 'Country', value: subject.country),
          if ((subject.additionalInfo ?? '').trim().isNotEmpty)
            _SubjectField(
              label: 'Additional info',
              value: subject.additionalInfo!,
            ),
          if (subject.photoUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('Photos', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: subject.photoUrls.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.sm),
                itemBuilder: (_, i) {
                  final String url = subject.photoUrls[i];
                  return GestureDetector(
                    onTap: () => showFullscreenImage(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      child: AdaptiveImage(
                        reference: url,
                        width: 72,
                        height: 72,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          if (subject.documentUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text('Documents', style: text.labelSmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                for (int i = 0; i < subject.documentUrls.length; i++)
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: Text('Document ${i + 1}'),
                    onPressed: () => _openSubjectFile(
                      context,
                      subject.documentUrls[i],
                      'Document ${i + 1}',
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectField extends StatelessWidget {
  const _SubjectField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// Form fields for the Finder research role.
class _FinderForm extends StatefulWidget {
  const _FinderForm({
    required this.header,
    required this.submission,
    required this.onChanged,
  });
  final Widget header;
  final FinderSubmission submission;
  final ValueChanged<FinderSubmission> onChanged;

  @override
  State<_FinderForm> createState() => _FinderFormState();
}

class _FinderFormState extends State<_FinderForm> {
  late FinderSubmission _submission;

  @override
  void initState() {
    super.initState();
    _submission = widget.submission;
  }

  void _notify() {
    widget.onChanged(_submission);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        widget.header,
        _SectionTitle(title: 'Research summary', icon: Icons.article_outlined),
        TextField(
          controller: TextEditingController(text: _submission.summary)
            ..selection = TextSelection.collapsed(
              offset: _submission.summary?.length ?? 0,
            ),
          maxLines: 3,
          onChanged: (v) {
            _submission = _submission.copyWith(summary: v);
            _notify();
          },
          decoration: const InputDecoration(
            hintText: 'Brief summary of what you found',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'Sources', icon: Icons.folder_open_outlined),
        ..._submission.sources.asMap().entries.map((entry) {
          final index = entry.key;
          final source = entry.value;
          return _SourceCard(
            source: source,
            onChanged: (s) {
              final sources = <ResearchSource>[..._submission.sources];
              sources[index] = s;
              _submission = _submission.copyWith(sources: sources);
              _notify();
            },
            onDelete: () {
              final sources = <ResearchSource>[..._submission.sources];
              sources.removeAt(index);
              _submission = _submission.copyWith(sources: sources);
              _notify();
              setState(() {});
            },
          );
        }),
        TextButton.icon(
          onPressed: () {
            _submission = _submission.copyWith(
              sources: <ResearchSource>[
                ..._submission.sources,
                const ResearchSource(),
              ],
            );
            _notify();
            setState(() {});
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add source'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(
          title: 'Evidence evaluation',
          icon: Icons.balance_outlined,
        ),
        TextField(
          controller: TextEditingController(text: _submission.evidenceNotes)
            ..selection = TextSelection.collapsed(
              offset: _submission.evidenceNotes?.length ?? 0,
            ),
          maxLines: 3,
          onChanged: (v) {
            _submission = _submission.copyWith(evidenceNotes: v);
            _notify();
          },
          decoration: const InputDecoration(
            hintText: 'Conflicts resolved, reasoning, proof summary',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String?>(
          value: _submission.confidenceLevel,
          decoration: const InputDecoration(labelText: 'Confidence level'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Select...'),
            ),
            const DropdownMenuItem<String?>(value: 'high', child: Text('High')),
            const DropdownMenuItem<String?>(
              value: 'medium',
              child: Text('Medium'),
            ),
            const DropdownMenuItem<String?>(value: 'low', child: Text('Low')),
          ],
          onChanged: (v) {
            _submission = _submission.copyWith(confidenceLevel: v);
            _notify();
            setState(() {});
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'DNA analysis', icon: Icons.biotech_outlined),
        TextField(
          controller: TextEditingController(text: _submission.dnaNotes)
            ..selection = TextSelection.collapsed(
              offset: _submission.dnaNotes?.length ?? 0,
            ),
          maxLines: 3,
          onChanged: (v) {
            _submission = _submission.copyWith(dnaNotes: v);
            _notify();
          },
          decoration: const InputDecoration(
            hintText: 'Genetic matches, haplogroups, shared cM, etc.',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(
          title: 'Compiled report / chart',
          icon: Icons.description_outlined,
        ),
        TextField(
          controller: TextEditingController(text: _submission.report)
            ..selection = TextSelection.collapsed(
              offset: _submission.report?.length ?? 0,
            ),
          maxLines: 5,
          onChanged: (v) {
            _submission = _submission.copyWith(report: v);
            _notify();
          },
          decoration: const InputDecoration(
            hintText: 'Paste the final report, chart outline, or conclusions',
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onChanged,
    required this.onDelete,
  });

  final ResearchSource source;
  final ValueChanged<ResearchSource> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: <Widget>[
            TextField(
              controller: TextEditingController(text: source.title)
                ..selection = TextSelection.collapsed(
                  offset: source.title.length,
                ),
              decoration: const InputDecoration(hintText: 'Source title'),
              onChanged: (v) => onChanged(source.copyWith(title: v)),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: TextEditingController(text: source.url)
                ..selection = TextSelection.collapsed(
                  offset: source.url?.length ?? 0,
                ),
              decoration: const InputDecoration(
                hintText: 'URL or archive reference',
              ),
              onChanged: (v) => onChanged(source.copyWith(url: v)),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: TextEditingController(text: source.date)
                ..selection = TextSelection.collapsed(
                  offset: source.date?.length ?? 0,
                ),
              decoration: const InputDecoration(hintText: 'Record date'),
              onChanged: (v) => onChanged(source.copyWith(date: v)),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: TextEditingController(text: source.notes)
                ..selection = TextSelection.collapsed(
                  offset: source.notes?.length ?? 0,
                ),
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Notes about this source',
              ),
              onChanged: (v) => onChanged(source.copyWith(notes: v)),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Form fields for the Indexer transcription role.
class _IndexerForm extends StatefulWidget {
  const _IndexerForm({
    required this.header,
    required this.submission,
    required this.onChanged,
  });
  final Widget header;
  final IndexerSubmission submission;
  final ValueChanged<IndexerSubmission> onChanged;

  @override
  State<_IndexerForm> createState() => _IndexerFormState();
}

class _IndexerFormState extends State<_IndexerForm> {
  late IndexerSubmission _submission;

  @override
  void initState() {
    super.initState();
    _submission = widget.submission;
  }

  void _notify() {
    widget.onChanged(_submission);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: <Widget>[
        widget.header,
        _SectionTitle(
          title: 'Original image / scan',
          icon: Icons.image_outlined,
        ),
        TextField(
          controller: TextEditingController(text: _submission.originalImageUrl)
            ..selection = TextSelection.collapsed(
              offset: _submission.originalImageUrl?.length ?? 0,
            ),
          decoration: const InputDecoration(
            hintText: 'Link to the scanned document image',
          ),
          onChanged: (v) {
            _submission = _submission.copyWith(originalImageUrl: v);
            _notify();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'Transcription', icon: Icons.keyboard_outlined),
        TextField(
          controller: TextEditingController(text: _submission.transcription)
            ..selection = TextSelection.collapsed(
              offset: _submission.transcription?.length ?? 0,
            ),
          maxLines: 8,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: 'Type the full text from the document here',
            alignLabelWithHint: true,
          ),
          onChanged: (v) {
            _submission = _submission.copyWith(transcription: v);
            _notify();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'Quality checks', icon: Icons.fact_check_outlined),
        ...QualityCheck.values.map((check) {
          return CheckboxListTile(
            title: Text(check.label),
            value: _submission.qualityChecks.contains(check),
            onChanged: (selected) {
              final checks = <QualityCheck>[..._submission.qualityChecks];
              if (selected == true) {
                checks.add(check);
              } else {
                checks.remove(check);
              }
              _submission = _submission.copyWith(qualityChecks: checks);
              _notify();
              setState(() {});
            },
          );
        }),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'Keywords / tags', icon: Icons.tag_outlined),
        TextField(
          controller: TextEditingController(text: _submission.keywords)
            ..selection = TextSelection.collapsed(
              offset: _submission.keywords?.length ?? 0,
            ),
          decoration: const InputDecoration(
            hintText: 'occupation, military rank, religion, etc.',
          ),
          onChanged: (v) {
            _submission = _submission.copyWith(keywords: v);
            _notify();
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _SectionTitle(title: 'Indexer notes', icon: Icons.notes_outlined),
        TextField(
          controller: TextEditingController(text: _submission.notes)
            ..selection = TextSelection.collapsed(
              offset: _submission.notes?.length ?? 0,
            ),
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Faded text, torn pages, or other issues to flag',
          ),
          onChanged: (v) {
            _submission = _submission.copyWith(notes: v);
            _notify();
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
