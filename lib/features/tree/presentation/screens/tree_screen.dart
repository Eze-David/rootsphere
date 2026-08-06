import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../data/services/tree_pdf_service.dart';
import '../../domain/entities/person.dart';
import '../layout/tree_layout.dart';
import '../painters/tree_connector_painter.dart';
import '../providers/tree_providers.dart';
import '../widgets/person_card_widget.dart';
import '../widgets/person_actions_sheet.dart';
import '../widgets/person_editor_sheet.dart';
import '../widgets/tree_node_widgets.dart';
import '../../../../shared/widgets/zoom_controls.dart';

/// The Phase 2 centrepiece: an interactive, pan/zoom family-tree renderer with
/// Ancestors / Descendants / Pedigree modes.
/// The three mutually-exclusive options in the app-bar "view" menu — the
/// first two select [TreeViewMode.graph] plus a [TreeOrientation], the third
/// selects [TreeViewMode.list] (which has no orientation of its own).
enum _TreeViewOption { vertical, horizontal, list }

class TreeScreen extends ConsumerStatefulWidget {
  const TreeScreen({super.key});

  @override
  ConsumerState<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends ConsumerState<TreeScreen> {
  final TransformationController _controller = TransformationController();
  Size _viewport = Size.zero;
  bool _didInitialFit = false;
  TreeOrientation? _lastOrientation;
  bool _printing = false;

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
    final Matrix4 inverse =
        Matrix4.tryInvert(_controller.value) ?? Matrix4.identity();
    final Offset topLeft = MatrixUtils.transformPoint(inverse, Offset.zero);
    final Offset bottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(_viewport.width, _viewport.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
  }

  /// The zoom level every fresh focus (a new branch, a search result, the
  /// "reset zoom" button) starts at. Every call site that reaches
  /// [_centerOnFocus] represents switching to a different layout — never a
  /// same-layout resize — so there's no "current zoom" worth preserving;
  /// carrying over whatever scale a pinch-zoom left on the *previous*
  /// branch made the same 1.5px connector stroke width render at visibly
  /// different sizes depending on which branch you'd zoomed on last (e.g.
  /// a spouse's ancestors looking thicker than the main line's).
  static const double _defaultFocusScale = 1.0;

  void _centerOnFocus(TreeLayout layout) {
    if (_viewport == Size.zero) return;
    final Rect f = layout.focusRect;
    const double scale = _defaultFocusScale;
    final bool horizontal =
        ref.read(treeOrientationProvider) == TreeOrientation.horizontal;
    // Vertical: focus near the bottom (ancestors above). Horizontal: focus
    // near the left (ancestors to the right).
    final double anchorX = horizontal ? 0.28 : 0.5;
    final double anchorY = horizontal ? 0.5 : 0.72;
    final double tx = _viewport.width * anchorX - f.center.dx * scale;
    final double ty = _viewport.height * anchorY - f.center.dy * scale;
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  /// Multiplies the current zoom by [factor], keeping the viewport centre fixed.
  void _zoomBy(double factor) {
    if (_viewport == Size.zero) return;
    final Matrix4 m = _controller.value;
    final double scale = m.getMaxScaleOnAxis();
    final double target = (scale * factor).clamp(0.2, 4.0);
    if ((target - scale).abs() < 1e-6) return;

    final Matrix4 inverse = Matrix4.tryInvert(m) ?? Matrix4.identity();
    final Offset centre = Offset(_viewport.width / 2, _viewport.height / 2);
    final Offset scenePoint = MatrixUtils.transformPoint(inverse, centre);
    final double tx = centre.dx - scenePoint.dx * target;
    final double ty = centre.dy - scenePoint.dy * target;
    _controller.value = Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(target, target, target, 1);
  }

  void _resetZoom(TreeLayout layout) {
    _didInitialFit = false;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnFocus(layout));
  }

  /// Focuses the tree on a person found via search and re-centers on them.
  ///
  /// Unlike a plain camera pan, this sets them as the tree's focus (like
  /// "Center on this person" on the card menu) — searching only panned to an
  /// already-rendered node before, so picking someone outside the current
  /// focus's ancestors/spouse/children (e.g. a different branch entirely)
  /// silently did nothing, since they simply weren't in that layout.
  Future<void> _showSearch(List<Person> persons) async {
    final Person? selected = await showDialog<Person>(
      context: context,
      builder: (context) => _TreeSearchDialog(persons: persons),
    );
    if (selected == null || !mounted) return;

    setFocusPerson(ref, selected.id);
    final TreeLayout? newLayout = ref.read(treeLayoutProvider);
    if (newLayout == null) return;
    _didInitialFit = false;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerOnFocus(newLayout),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AsyncValue<List<Person>> personsAsync = ref.watch(personsProvider);
    final TreeMode mode = ref.watch(treeModeProvider);
    final TreeOrientation orientation = ref.watch(treeOrientationProvider);
    final TreeViewMode viewMode = ref.watch(treeViewModeProvider);
    final TreeLayout? layout = ref.watch(treeLayoutProvider);
    final int generations = layout?.generations ?? 0;
    final treeId = ref.watch(activeTreeIdProvider);

    // Re-fit the view whenever the orientation flips.
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      _didInitialFit = false;
    }

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
        // Zoom in/out/recenter used to live here too, but 7 action icons
        // (each needing ~48dp) plus the leading button overflows AppBars on
        // phones narrower than ~400dp — most Android devices, not just the
        // budget end — silently clipping the trailing icons off-screen
        // rather than throwing a visible overflow error. They're a floating
        // cluster over the canvas instead (see _buildCanvas below).
        actions: <Widget>[
          PopupMenuButton<_TreeViewOption>(
            tooltip: 'View',
            icon: Icon(
              viewMode == TreeViewMode.list
                  ? Icons.view_list_outlined
                  : orientation == TreeOrientation.vertical
                  ? Icons.account_tree_outlined
                  : Icons.account_tree,
            ),
            onSelected: (o) {
              switch (o) {
                case _TreeViewOption.vertical:
                  ref.read(treeViewModeProvider.notifier).state =
                      TreeViewMode.graph;
                  ref.read(treeOrientationProvider.notifier).state =
                      TreeOrientation.vertical;
                case _TreeViewOption.horizontal:
                  ref.read(treeViewModeProvider.notifier).state =
                      TreeViewMode.graph;
                  ref.read(treeOrientationProvider.notifier).state =
                      TreeOrientation.horizontal;
                case _TreeViewOption.list:
                  ref.read(treeViewModeProvider.notifier).state =
                      TreeViewMode.list;
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_TreeViewOption>>[
              CheckedPopupMenuItem<_TreeViewOption>(
                value: _TreeViewOption.vertical,
                checked:
                    viewMode == TreeViewMode.graph &&
                    orientation == TreeOrientation.vertical,
                child: const Text('Vertical'),
              ),
              CheckedPopupMenuItem<_TreeViewOption>(
                value: _TreeViewOption.horizontal,
                checked:
                    viewMode == TreeViewMode.graph &&
                    orientation == TreeOrientation.horizontal,
                child: const Text('Horizontal'),
              ),
              CheckedPopupMenuItem<_TreeViewOption>(
                value: _TreeViewOption.list,
                checked: viewMode == TreeViewMode.list,
                child: const Text('List'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Search people',
            icon: const Icon(Icons.search),
            onPressed: layout == null
                ? null
                : () => _showSearch(
                    ref.read(personsProvider).value ?? const <Person>[],
                  ),
          ),
          if (viewMode == TreeViewMode.graph)
            IconButton(
              tooltip: 'Print family tree',
              icon: _printing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print_outlined),
              onPressed: layout == null || _printing
                  ? null
                  : () => _printTree(layout, treeId),
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
          if (persons.isEmpty) {
            return _EmptyTree(onAdd: () => _addRootPerson(context, treeId));
          }
          if (viewMode == TreeViewMode.list) {
            return _PersonListView(
              persons: persons,
              onTap: (p) => showPersonActionsSheet(context, ref, p),
            );
          }
          if (layout == null) {
            return _EmptyTree(onAdd: () => _addRootPerson(context, treeId));
          }
          return Column(
            children: <Widget>[
              Expanded(
                child: Stack(
                  children: <Widget>[
                    _buildCanvas(layout),
                    Positioned(
                      right: AppSpacing.lg,
                      bottom: AppSpacing.lg,
                      child: ZoomControls(
                        onZoomIn: () => _zoomBy(1.25),
                        onZoomOut: () => _zoomBy(0.8),
                        thirdIcon: Icons.center_focus_strong_outlined,
                        thirdTooltip: 'Recenter',
                        onThird: () => _resetZoom(layout),
                      ),
                    ),
                  ],
                ),
              ),
              _ModeToggle(
                mode: mode,
                onChanged: (m) => ref.read(treeModeProvider.notifier).state = m,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCanvas(TreeLayout layout) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final bool horizontal =
        ref.watch(treeOrientationProvider) == TreeOrientation.horizontal;
    final Color canvasBg = dark
        ? AppColors.treeCanvasDark
        : AppColors.treeCanvasLight;
    final Color connectorColor = AppColors.textTertiary.withValues(alpha: 0.7);

    return ColoredBox(
      color: canvasBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final Size newViewport = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
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

          // Viewport culling: only build elements intersecting the visible rect.
          final Rect cullRect = visible.inflate(160);
          final visibleNodes = layout.nodes
              .where((n) => n.rect.overlaps(cullRect))
              .toList();
          final visibleSlots = layout.slots
              .where((s) => s.rect.overlaps(cullRect))
              .toList();

          // Which spouse cards have relatives (parents/other marriages) this
          // view doesn't show at all — see PositionedPerson.isSpouseCard.
          final Set<String> renderedIds = layout.nodes
              .map((n) => n.person.id)
              .toSet();
          bool hasHiddenFamily(Person p) =>
              p.parentIds.any((id) => !renderedIds.contains(id)) ||
              p.spouseIds.any((id) => !renderedIds.contains(id));

          final List<PositionedPerson> badgeNodes = visibleNodes
              .where((n) => n.isSpouseCard && hasHiddenFamily(n.person))
              .toList();
          // Each badge sits just above its card's top-left corner, joined to
          // it by a short stub drawn through the same painter (and so the
          // same line style) as every other connector in the tree.
          final Map<String, Offset> badgeCenters = <String, Offset>{
            for (final n in badgeNodes)
              n.person.id: Offset(
                n.rect.left + 20,
                n.rect.top - SpouseFamilyBadge.size / 2 - 6,
              ),
          };
          final List<TreeConnector> badgeConnectors = <TreeConnector>[
            for (final n in badgeNodes)
              TreeConnector(
                points: <Offset>[
                  Offset(
                    badgeCenters[n.person.id]!.dx,
                    badgeCenters[n.person.id]!.dy + SpouseFamilyBadge.size / 2,
                  ),
                  Offset(n.rect.left + 20, n.rect.top),
                ],
                roundCap: false,
              ),
          ];

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
                        connectors: <TreeConnector>[
                          ...layout.connectors,
                          ...badgeConnectors,
                        ],
                        visibleRect: visible,
                        lineColor: connectorColor,
                        spouseColor: connectorColor,
                      ),
                    ),
                  ),
                  for (final label in layout.labels) _positionedLabel(label),
                  for (final slot in visibleSlots)
                    Positioned(
                      left: slot.rect.left,
                      top: slot.rect.top,
                      width: slot.rect.width,
                      height: slot.rect.height,
                      child: PlaceholderSlotWidget(
                        label: slot.label,
                        horizontal: horizontal,
                        onTap: () => _onSlotTap(slot),
                      ),
                    ),
                  for (final node in visibleNodes) ...<Widget>[
                    Positioned(
                      left: node.rect.left,
                      top: node.rect.top,
                      width: node.rect.width,
                      // The focus card (and its spouse, kept the same height
                      // for visual parity) reserves extra height for an
                      // inline "Add relative" footer, overflowing below its
                      // base rect. Skipped in horizontal orientation: there,
                      // the focus's spouse sits directly below it (breadth
                      // runs vertically there), close enough that this
                      // overflow would overlap the spouse's card. Tapping the
                      // card itself opens the same actions either way.
                      height:
                          ((node.isFocus || node.isSpouseCard) && !horizontal)
                          ? node.rect.height + TreeMetrics.focusFooter
                          : node.rect.height,
                      child: PersonCardWidget(
                        person: node.person,
                        isFocus: node.isFocus,
                        horizontal: horizontal,
                        onTap: () => _onCardTap(node.person),
                        onAddRelative:
                            ((node.isFocus || node.isSpouseCard) && !horizontal)
                            ? () => _onCardTap(node.person)
                            : null,
                      ),
                    ),
                    if (badgeCenters[node.person.id] case final Offset c)
                      Positioned(
                        left: c.dx - SpouseFamilyBadge.width / 2,
                        top: c.dy - SpouseFamilyBadge.height / 2,
                        width: SpouseFamilyBadge.width,
                        height: SpouseFamilyBadge.height,
                        child: SpouseFamilyBadge(
                          onTap: () => _openSpouseTree(node.person),
                        ),
                      ),
                  ],
                  for (final toggle in layout.toggles)
                    Positioned(
                      left: toggle.center.dx - CollapseToggleWidget.size / 2,
                      top: toggle.center.dy - CollapseToggleWidget.size / 2,
                      width: CollapseToggleWidget.size,
                      height: CollapseToggleWidget.size,
                      child: CollapseToggleWidget(
                        collapsed: toggle.collapsed,
                        onTap: () => _onToggle(toggle.personId),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _positionedLabel(GenerationLabel label) {
    const double w = 200;
    return Positioned(
      left: label.center.dx - w / 2,
      top: label.center.dy - 9,
      width: w,
      child: Text(
        label.text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _onToggle(String personId) {
    final notifier = ref.read(collapsedAncestorsProvider.notifier);
    final Set<String> next = <String>{...ref.read(collapsedAncestorsProvider)};
    if (!next.remove(personId)) next.add(personId);
    notifier.state = next;
  }

  Future<void> _onSlotTap(PositionedSlot slot) async {
    final Person? child = ref.read(personMapProvider)[slot.childId];
    if (child == null) return;
    final bool isFather = slot.kind == SlotKind.father;
    final Person? created = await showPersonEditorSheet(
      context,
      ref,
      treeId: child.treeId,
      relationLabel: isFather ? 'Add father' : 'Add mother',
      relativeOf: child.fullName,
      prefillSurname: isFather ? child.surname : null,
      defaultSex: isFather ? Sex.male : Sex.female,
    );
    if (created == null) return;
    await ref
        .read(treeRepositoryProvider)
        .linkChild(
          treeId: child.treeId,
          parentId: created.id,
          childId: child.id,
        );
  }

  void _onCardTap(Person person) {
    showPersonActionsSheet(context, ref, person);
  }

  /// Re-roots the tree onto [spouse] (see [SpouseFamilyBadge]) — their own
  /// parents/other marriages, invisible in the current view since a spouse's
  /// ancestry is never recursed into, become the pedigree once they're the
  /// focus. Mirrors [_showSearch]'s re-focus + re-pan sequence.
  void _openSpouseTree(Person spouse) {
    setFocusPerson(ref, spouse.id);
    final TreeLayout? newLayout = ref.read(treeLayoutProvider);
    if (newLayout == null) return;
    _didInitialFit = false;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerOnFocus(newLayout),
    );
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
    setFocusPerson(ref, created.id);
  }

  Future<void> _printTree(TreeLayout layout, String treeId) async {
    setState(() => _printing = true);
    try {
      final String treeName = _treeName(treeId);
      final String focusName = layout.nodes.isEmpty
          ? treeName
          : layout.nodes
                .firstWhere((n) => n.isFocus, orElse: () => layout.nodes.first)
                .person
                .fullName;
      final PdfPageFormat format = layout.size.width >= layout.size.height
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4;
      // Building the PDF fetches Google Fonts over the network the first
      // time, which can take a few seconds (or fail if offline) — the print
      // dialog only appears once this future resolves, so without the
      // loading spinner + error surfacing below, a slow or failed fetch
      // looks indistinguishable from the button doing nothing.
      final bool launched = await Printing.layoutPdf(
        format: format,
        name: '$treeName family tree.pdf',
        onLayout: (PdfPageFormat fmt) => TreePdfService.build(
          layout: layout,
          treeName: treeName,
          focusName: focusName,
          format: fmt,
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
          SnackBar(
            content: Text(
              'Could not prepare the PDF. Check your internet connection '
              'and try again. ($e)',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  String _treeName(String treeId) {
    if (treeId == 'okonkwo') return 'Okonkwo';
    if (treeId.startsWith('t_')) return 'My Family Tree';
    return treeId.isEmpty
        ? 'Untitled'
        : treeId[0].toUpperCase() + treeId.substring(1);
  }
}

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
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final Color primary = theme.colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? primary : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: selected ? primary : theme.dividerColor),
          ),
          child: Text(
            label,
            style: text.labelLarge?.copyWith(
              color: selected
                  ? AppColors.onPrimary
                  : theme.textTheme.bodyLarge?.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat, alphabetically-sorted list of every person in the tree — an
/// alternative to the graph for quickly scanning or picking someone out of a
/// large tree without panning/zooming. Tapping a row opens the same actions
/// sheet as tapping a card on the graph.
class _PersonListView extends StatelessWidget {
  const _PersonListView({required this.persons, required this.onTap});

  final List<Person> persons;
  final ValueChanged<Person> onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<Person> sorted = <Person>[...persons]
      ..sort(
        (a, b) =>
            a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final Person p = sorted[i];
        final String subtitle = <String>[
          if (p.lifespan.isNotEmpty) p.lifespan,
          if ((p.code ?? '').isNotEmpty) p.code!,
        ].join(' · ');
        return ListTile(
          leading: AdaptiveAvatar(reference: p.photoUrl, radius: 20),
          title: Text(p.fullName),
          subtitle: subtitle.isEmpty ? null : Text(subtitle, style: text.bodySmall),
          trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          onTap: () => onTap(p),
        );
      },
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

/// Search dialog for finding a person in the tree by name.
class _TreeSearchDialog extends StatefulWidget {
  const _TreeSearchDialog({required this.persons});

  final List<Person> persons;

  @override
  State<_TreeSearchDialog> createState() => _TreeSearchDialogState();
}

class _TreeSearchDialogState extends State<_TreeSearchDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Person> get _results {
    final String q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.persons;
    return widget.persons
        .where(
          (p) =>
              p.fullName.toLowerCase().contains(q) ||
              (p.code?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  /// Shows the birth year and/or ID code so a matching search result can be
  /// visually confirmed — most useful when several people share a name.
  Widget? _resultSubtitle(Person p, TextTheme text) {
    final String? code = p.code;
    final String year = p.birthDate != null ? '${p.birthDate!.year}' : '';
    final String label = <String>[
      if (year.isNotEmpty) year,
      if (code != null && code.isNotEmpty) code,
    ].join(' · ');
    return label.isEmpty ? null : Text(label, style: text.bodySmall);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text('Search people', style: text.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name or ID…',
                  prefixIcon: const Icon(
                    Icons.search,
                    color: AppColors.textTertiary,
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final Person p = _results[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.cream,
                        child: Text(
                          p.givenName.isNotEmpty
                              ? p.givenName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(color: AppColors.primary),
                        ),
                      ),
                      title: Text(p.fullName),
                      subtitle: _resultSubtitle(p, text),
                      onTap: () => Navigator.of(context).pop(p),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
