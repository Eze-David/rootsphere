import 'package:flutter/material.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_spacing.dart';

/// Bump (together with the version checked in check_claim_qualification)
/// whenever the wording changes, so everyone re-accepts the new text.
const String kUndertakingVersion = '2026-10';

/// (heading, commitment) pairs — also shown to admins reviewing signatures.
const List<(String, String)> undertakingClauses = <(String, String)>[
  (
    'Confidentiality',
    "I will keep every client's personal information, records, photographs "
        'and documents confidential, use them only for the assigned research, '
        'and not share, publish or retain them beyond what the research '
        'requires.',
  ),
  (
    'Accuracy and honesty',
    'I will never fabricate, alter or embellish records, relationships, '
        'dates or findings, and I will clearly separate proven facts from '
        'assumptions or hypotheses.',
  ),
  (
    'Citing sources',
    'I will properly cite the source of every record or piece of evidence I '
        'report, so the client and RootSphere can verify it.',
  ),
  (
    'Conflicts of interest',
    'I will disclose any personal, family or financial interest that could '
        'affect my work on a request before I begin.',
  ),
  (
    'Clients stay on the platform',
    'I will not privately approach, solicit or take a RootSphere client '
        'outside the platform, or arrange payment directly with them, '
        'without written authorization from RootSphere.',
  ),
  (
    'Respect and care',
    'I will treat clients, families, communities, archives and record '
        'custodians with respect, and handle original documents with care.',
  ),
];

/// Whether the signed-in user has accepted the current undertaking. Local
/// (no-Supabase) mode has no server enforcement, so it's treated as accepted.
Future<bool> hasAcceptedResearcherUndertaking() async {
  if (!SupabaseConfig.isReady) return true;
  final String? uid = SupabaseConfig.client.auth.currentUser?.id;
  if (uid == null) return false;
  final Map<String, dynamic>? row = await SupabaseConfig.client
      .from('researcher_undertakings')
      .select('user_id')
      .eq('user_id', uid)
      .eq('version', kUndertakingVersion)
      .maybeSingle();
  return row != null;
}

/// Makes sure the user has accepted the Researcher Code of Conduct and
/// Confidentiality Undertaking, showing it if they haven't. Returns true when
/// they may go ahead and claim.
Future<bool> ensureResearcherUndertaking(BuildContext context) async {
  if (await hasAcceptedResearcherUndertaking()) return true;
  if (!context.mounted) return false;
  final bool? accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _UndertakingSheet(),
  );
  return accepted ?? false;
}

class _UndertakingSheet extends StatefulWidget {
  const _UndertakingSheet();

  @override
  State<_UndertakingSheet> createState() => _UndertakingSheetState();
}

class _UndertakingSheetState extends State<_UndertakingSheet> {
  final TextEditingController _nameController = TextEditingController();
  bool _agreed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? meta =
        SupabaseConfig.client.auth.currentUser?.userMetadata;
    _nameController.text =
        (meta?['full_name'] ?? meta?['name'] ?? meta?['display_name'] ?? '')
            .toString();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Type your full name to sign.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client
          .from('researcher_undertakings')
          .insert(<String, dynamic>{
            'user_id': SupabaseConfig.client.auth.currentUser!.id,
            'version': kUndertakingVersion,
            'signed_name': name,
          });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: ${friendlyErrorMessage(e)}')),
        );
      }
    }
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
              'ROOTSPHERE FAMILY HISTORY FOUNDATION',
              style: text.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Researcher Code of Conduct',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              'and Confidentiality Undertaking',
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Before claiming your first opportunity, please read and accept '
              'the commitments every RootSphere researcher and volunteer makes.',
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < undertakingClauses.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        '${i + 1}',
                        style: text.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            undertakingClauses[i].$1,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(undertakingClauses[i].$2, style: text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Breaching this undertaking may lead to removal from the '
              'collaboration board and loss of verified researcher status.',
              style: text.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name (signature)',
              ),
            ),
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I have read and agree to the Code of Conduct and '
                'Confidentiality Undertaking',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _agreed && !_saving ? _accept : null,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Accept and continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
