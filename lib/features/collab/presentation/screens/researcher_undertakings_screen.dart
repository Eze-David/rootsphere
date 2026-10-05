import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/theme/app_spacing.dart';
import '../widgets/researcher_undertaking_sheet.dart';

/// One signed Researcher Code of Conduct and Confidentiality Undertaking.
class SignedUndertaking {
  const SignedUndertaking({
    required this.userId,
    required this.signedName,
    required this.email,
    required this.version,
    required this.acceptedAt,
  });

  final String userId;
  final String signedName;
  final String? email;
  final String version;
  final DateTime acceptedAt;

  factory SignedUndertaking.fromRow(Map<String, dynamic> row) {
    return SignedUndertaking(
      userId: row['user_id'] as String,
      signedName: row['signed_name'] as String? ?? '',
      email: row['email'] as String?,
      version: row['version'] as String? ?? '',
      acceptedAt: DateTime.parse(row['accepted_at'] as String).toLocal(),
    );
  }
}

/// Admin-only: every signed undertaking, newest first (the
/// `list_researcher_undertakings` RPC rejects non-admins server-side).
final signedUndertakingsProvider =
    FutureProvider.autoDispose<List<SignedUndertaking>>((ref) async {
      if (!SupabaseConfig.isReady) return const <SignedUndertaking>[];
      final List<dynamic> rows = await SupabaseConfig.client.rpc(
        'list_researcher_undertakings',
      );
      return rows
          .map((r) => SignedUndertaking.fromRow(r as Map<String, dynamic>))
          .toList();
    });

class ResearcherUndertakingsScreen extends ConsumerWidget {
  const ResearcherUndertakingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SignedUndertaking>> async = ref.watch(
      signedUndertakingsProvider,
    );
    final TextTheme text = Theme.of(context).textTheme;
    final Color muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Signed codes of conduct')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(
              'Could not load: ${friendlyErrorMessage(e)}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.gavel_outlined, size: 48, color: muted),
                    const SizedBox(height: AppSpacing.md),
                    Text('No signatures yet', style: text.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Researchers appear here once they accept the Code of '
                      'Conduct before their first claim.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(signedUndertakingsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, i) {
                final SignedUndertaking u = items[i];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.verified_user_outlined),
                    title: Text(u.signedName),
                    subtitle: Text(
                      <String>[
                        if ((u.email ?? '').isNotEmpty) u.email!,
                        '${_formatDate(context, u.acceptedAt)} · v${u.version}',
                      ].join('\n'),
                    ),
                    isThreeLine: (u.email ?? '').isNotEmpty,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showSigned(context, u),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

String _formatDate(BuildContext context, DateTime d) {
  final MaterialLocalizations l = MaterialLocalizations.of(context);
  return '${l.formatMediumDate(d)}, '
      '${l.formatTimeOfDay(TimeOfDay.fromDateTime(d))}';
}

/// The undertaking exactly as the researcher accepted it, with their
/// signature block — a record the admin can refer back to.
Future<void> _showSigned(BuildContext context, SignedUndertaking u) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final ThemeData theme = Theme.of(ctx);
      final TextTheme text = theme.textTheme;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Researcher Code of Conduct and Confidentiality Undertaking',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            for (int i = 0; i < undertakingClauses.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${i + 1}. ${undertakingClauses[i].$1}: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(text: undertakingClauses[i].$2),
                    ],
                  ),
                  style: text.bodySmall,
                ),
              ),
            const Divider(height: AppSpacing.xl),
            Text('Signed by', style: text.labelSmall),
            Text(u.signedName, style: text.titleSmall),
            if ((u.email ?? '').isNotEmpty)
              Text(u.email!, style: text.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Text('Accepted', style: text.labelSmall),
            Text(
              '${_formatDate(ctx, u.acceptedAt)} · version ${u.version}',
              style: text.bodyMedium,
            ),
          ],
        ),
      );
    },
  );
}
