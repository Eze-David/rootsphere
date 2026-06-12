import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/person.dart';
import '../layout/tree_layout.dart';
import '../painters/tree_connector_painter.dart';
import '../providers/tree_providers.dart';
import '../widgets/person_card_widget.dart';
import '../widgets/person_actions_sheet.dart';
import '../widgets/person_editor_sheet.dart';

/// The Phase 2 centrepiece: an interactive, pan/zoom family-tree renderer with
/// Ancestors / Descendants / Pedigree modes.
class TreeScreen extends ConsumerStatefulWidget {
  const TreeScreen({super.key});

  @override
  ConsumerState<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends ConsumerState<TreeScreen> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformChanged() => setState(() {});

  /// Visible rectangle in scene (content) coordinates, for culling.
  Rect get _visibleSceneRect {
    if (_viewport == Size.zero) return Rect.largest;
    final Matrix4 inverse = Matrix4.tryInvert(_controller.value) ?? Matrix4.identity();
    final Offset topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final Offset bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(_viewport.width, _viewport.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _centerOnFocus(TreeLayout layout) {
    if (_viewport == Size.zero) return;
    final Rect f = layout.focusRect;
    final double scale = _controller.value.getMaxScaleOnAxis().clamp(0.1, 4.0);
    final double tx = _viewport.width / 2 - f.center.dx * scale;
    final double ty = _viewport.height / 3 - f.center.dy * scale;
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _resetZoom(TreeLayout layout) {
    _didInitialFit = false;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnFocus(layout));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<Person>> personsAsync = ref.watch(personsProvider);
    final TreeMode mode = ref.watch(treeModeProvider);
    final TreeLayout? layout = ref.watch(treeLayoutProvider);
    final int generations = layout?.generations ?? 0;
    final treeId = ref.watch(activeTreeIdProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('Family Tree', style: text.titleLarge),
            Text(
              '${_treeName(treeId)} · $generations generation'
              '${generations == 1 ? '' : 's'}',
              style: text.bodyMedium,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recenter',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: layout == null ? null : () => _resetZoom(layout),
          ),
          IconButton(
            tooltip: 'Add person',
            icon: const Icon(Icons.add),
            onPressed: () => _addRootPerson(context, treeId),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: personsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load tree: $e')),
        data: (persons) {
          if (persons.isEmpty || layout == null) {
            return _EmptyTree(onAdd: () => _addRootPerson(context, treeId));
          }
          return Column(
            children: <Widget>[
              Expanded(child: _buildCanvas(layout)),
              _ModeToggle(
                mode: mode,
                onChanged: (m) =>
                    ref.read(treeModeProvider.notifier).state = m,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvas(TreeLayout layout) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size newViewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (newViewport != _viewport) {
          _viewport = newViewport;
        }
        if (!_didInitialFit && _viewport != Size.zero) {
          _didInitialFit = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _centerOnFocus(layout),
          );
        }

        final Rect visible = _visibleSceneRect;

        // Viewport culling for cards: only build those intersecting the
        // (inflated) visible rect.
        final Rect cullRect = visible.inflate(120);
        final visibleNodes = layout.nodes
            .where((n) => n.rect.overlaps(cullRect))
            .toList();

        return InteractiveViewer(
          transformationController: _controller,
          minScale: 0.2,
          maxScale: 4.0,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          constrained: false,
          child: SizedBox(
            width: layout.size.width,
            height: layout.size.height,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: TreeConnectorPainter(
                      connectors: layout.connectors,
                      visibleRect: visible,
                    ),
                  ),
                ),
                for (final node in visibleNodes)
                  Positioned(
                    left: node.rect.left,
                    top: node.rect.top,
                    width: node.rect.width,
                    height: node.rect.height,
                    child: PersonCardWidget(
                      person: node.person,
                      isFocus: node.isFocus,
                      onTap: () => _onCardTap(node.person),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onCardTap(Person person) {
    showPersonActionsSheet(context, ref, person);
  }

  Future<void> _addRootPerson(BuildContext context, String treeId) async {
    final Person? created = await showPersonEditorSheet(
      context,
      ref,
      treeId: treeId,
      enableLinking: true,
    );
    if (created == null) return;

    // Focus the new person so they're visible — whether they were linked via
    // the in-form "Add to tree" picker or added standalone.
    ref.read(focusPersonIdProvider.notifier).state = created.id;
  }

  String _treeName(String treeId) {
    if (treeId == 'okonkwo') return 'Okonkwo';
    if (treeId.startsWith('t_')) return 'My Family Tree';
    return treeId.isEmpty
        ? 'Untitled'
        : treeId[0].toUpperCase() + treeId.substring(1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final TreeMode mode;
  final ValueChanged<TreeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Row(
          children: <Widget>[
            _ModeButton(
              label: 'Ancestors',
              selected: mode == TreeMode.ancestors,
              onTap: () => onChanged(TreeMode.ancestors),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ModeButton(
              label: 'Descendants',
              selected: mode == TreeMode.descendants,
              onTap: () => onChanged(TreeMode.descendants),
            ),
            const SizedBox(width: AppSpacing.sm),
            _ModeButton(
              label: 'Pedigree',
              selected: mode == TreeMode.pedigree,
              onTap: () => onChanged(TreeMode.pedigree),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.background,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: selected ? AppColors.onPrimary : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTree extends StatelessWidget {
  const _EmptyTree({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: const Icon(
                Icons.park_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            AppSpacing.gapLg,
            Text('Start your family tree', style: text.headlineMedium),
            AppSpacing.gapSm,
            Text(
              'Add your first person to begin building.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            AppSpacing.gapXl,
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add person'),
            ),
          ],
        ),
      ),
    );
  }
}
