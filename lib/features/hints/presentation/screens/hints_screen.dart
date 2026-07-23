import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/hint.dart';
import '../providers/hint_providers.dart';
import '../widgets/hint_card.dart';

/// Confidence-ranked AI / heuristic hints with an accept (apply) / dismiss flow
/// (brief §Phase 4 — Hints & AI).
class HintsScreen extends ConsumerStatefulWidget {
  const HintsScreen({super.key});

  @override
  ConsumerState<HintsScreen> createState() => _HintsScreenState();
}

class _HintsScreenState extends ConsumerState<HintsScreen> {
  String? _busyId;

  Future<void> _accept(Hint hint) async {
    setState(() => _busyId = hint.id);
    final String message =
        await ref.read(hintControllerProvider.notifier).accept(hint);
    if (mounted) {
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _dismiss(Hint hint) async {
    setState(() => _busyId = hint.id);
    await ref.read(hintControllerProvider.notifier).dismiss(hint);
    if (mounted) setState(() => _busyId = null);
  }

  void _open(Hint hint) {
    if (hint.personId != null) {
      context.push('${AppRoutes.person}/${hint.personId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Hint> hints = ref.watch(pendingHintsProvider);
    final HintsUiState ui = ref.watch(hintControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hints'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Generate hints',
            icon: const Icon(Icons.auto_awesome_outlined),
            onPressed: ui.generating
                ? null
                : () => ref.read(hintControllerProvider.notifier).generate(),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (ui.generating) const LinearProgressIndicator(minHeight: 2),
          if (ui.message != null)
            Container(
              width: double.infinity,
              color: AppColors.cream,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(ui.message!, style: text.bodySmall)),
                ],
              ),
            ),
          Expanded(
            child: hints.isEmpty
                ? _EmptyState(generating: ui.generating)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.xxl,
                    ),
                    itemCount: hints.length,
                    itemBuilder: (_, i) {
                      final Hint h = hints[i];
                      return HintCard(
                        hint: h,
                        busy: _busyId == h.id,
                        onAccept: () => _accept(h),
                        onDismiss: () => _dismiss(h),
                        onTap: () => _open(h),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState({required this.generating});
  final bool generating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    if (generating) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.auto_awesome_outlined,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('No hints right now', style: text.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Generate suggestions to discover missing data, possible '
              'duplicates, record matches and relationships.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(hintControllerProvider.notifier).generate(),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate hints'),
            ),
          ],
        ),
      ),
    );
  }
}
