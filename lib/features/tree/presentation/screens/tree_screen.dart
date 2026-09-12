import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/adaptive_image.dart';
import '../../../../shared/widgets/error_retry_view.dart';
import '../../data/services/tree_pdf_service.dart';
import '../../domain/entities/person.dart';
import '../layout/tree_layout.dart';
import '../painters/tree_connector_painter.dart';
import '../providers/tree_providers.dart';
import '../widgets/person_card_widget.dart';
import '../widgets/person_actions_sheet.dart';
import '../widgets/person_editor_sheet.dart';
import '../widgets/tree_node_widgets.dart';

/// The Phase 2 centrepiece: an interactive, pan/zoom family-tree renderer with
/// Ancestors / Descendants / Pedigree modes.
/// The three mutually-exclusive options in the [_ViewModeToggle] pill row —
/// the first two select [TreeViewMode.graph] plus a [TreeOrientation], the
/// third selects [TreeViewMode.list] (which has no orientation of its own).
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
  TreeMode? _lastMode;
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
    final bool descendants = ref.read(treeModeProvider) == TreeMode.descendants;
    // Descendants always grow straight down from the focus (the orientation
    // toggle only affects the ancestors layout), so anchoring it near the
    // bottom — correct for ancestors, who grow upward — left almost no room
    // below the focus and rendered most of the tree past the visible edge.
    // Vertical ancestors: focus near the bottom (ancestors above).
    // Horizontal ancestors: focus near the left (ancestors to the right).
    final double anchorX = descendants ? 0.5 : (horizontal ? 0.28 : 0.5);
    final double anchorY = descendants ? 0.22 : (horizontal ? 0.5 : 0.72);
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

  /// The flat person list has no descendants/ancestors distinction of its
  /// own — it always shows everyone, alphabetically — so toggling mode while
  /// List is active changed nothing on screen even though List stayed
  /// highlighted, making the tap look like it had no effect. Switching to
  /// the graph canvas when the mode changes makes every tap visible.
  void _onModeChanged(TreeMode m) {
    ref.read(treeModeProvider.notifier).state = m;
    if (ref.read(treeViewModeProvider) == TreeViewMode.list) {
      ref.read(treeViewModeProvider.notifier).state = TreeViewMode.graph;
    }
    // The descendants layout is always top-down (it has no horizontal
    // variant, unlike the ancestors pedigree) — forcing vertical here stops
    // the orientation from getting stuck on horizontal from a previous
    // ancestors view, which rendered the landscape card style over a tree
    // shape that never actually reflows for it.
    if (m == TreeMode.descendants) {
      ref.read(treeOrientationProvider.notifier).state =
          TreeOrientation.vertical;
    }
  }

  void _onViewOptionSelected(_TreeViewOption o) {
    // Vertical/Horizontal/List and Descendant are one mutually-exclusive
    // set of four styles, not two independently-toggled axes — picking any
    // of these three always drops back to the ancestors view.
    ref.read(treeModeProvider.notifier).state = TreeMode.ancestors;
    switch (o) {
      case _TreeViewOption.vertical:
        ref.read(treeViewModeProvider.notifier).state = TreeViewMode.graph;
        ref.read(treeOrientationProvider.notifier).state =
            TreeOrientation.vertical;
      case _TreeViewOption.horizontal:
        ref.read(treeViewModeProvider.notifier).state = TreeViewMode.graph;
        ref.read(treeOrientationProvider.notifier).state =
            TreeOrientation.horizontal;
      case _TreeViewOption.list:
        ref.read(treeViewModeProvider.notifier).state = TreeViewMode.list;
    }
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

    // Re-fit the view whenever the orientation flips or the ancestors/
    // descendants mode changes — otherwise the viewport stays panned to
    // wherever the previous layout was, and the newly-built layout can end
    // up rendering entirely off-screen (a blank canvas).
    if (orientation != _lastOrientation) {
      _lastOrientation = orientation;
      _didInitialFit = false;
    }
    if (mode != _lastMode) {
      _lastMode = mode;
      _didInitialFit = false;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.lg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Image.asset(
                  'assets/images/rootsphere-logo-espresso-v6-cropped.png',
                  width: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text('RootSphere Family Tree', style: text.titleLarge),
              ],
            ),
            Text(
              '${_treeName(treeId)} · $generations generation'
              '${generations == 1 ? '' : 's'}',
              style: text.bodyMedium,
            ),
          ],
        ),
        // Search/Print/zoom/recenter never lived in the AppBar's actions —
        // 7 action icons (each needing ~48dp) plus the leading button
        // overflows AppBars on phones narrower than ~400dp — most Android
        // devices, not just the budget end — silently clipping the trailing
        // icons off-screen rather than throwing a visible overflow error.
        // They're a single floating cluster over the canvas instead (see
        // _buildCanvas below), alongside List mode's own floating Search
        // button.
      ),
      body: personsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(
          error: e,
          onRetry: () => ref.invalidate(personsProvider),
        ),
        data: (persons) {
          if (persons.isEmpty) {
            return _EmptyTree(onAdd: () => _addRootPerson(context, treeId));
          }
          if (viewMode == TreeViewMode.list) {
            return Column(
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      _PersonListView(
                        persons: persons,
                        onTap: (p) => showPersonActionsSheet(context, ref, p),
                      ),
                      Positioned(
                        right: AppSpacing.lg,
                        bottom: AppSpacing.lg,
                        child: _CanvasActionCluster(
                          children: <Widget>[
                            IconButton(
                              tooltip: 'Search people',
                              icon: const Icon(Icons.search),
                              onPressed: () => _showSearch(persons),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _ViewModeToggle(
                  viewMode: viewMode,
                  orientation: orientation,
                  mode: mode,
                  onSelected: _onViewOptionSelected,
                  onModeChanged: _onModeChanged,
                ),
              ],
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
                      child: _CanvasActionCluster(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Search people',
                            icon: const Icon(Icons.search),
                            onPressed: () => _showSearch(persons),
                          ),
                          const Divider(height: 1),
                          IconButton(
                            tooltip: 'Print family tree',
                            icon: _printing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.print_outlined),
                            onPressed: _printing
                                ? null
                                : () => _printTree(layout, treeId),
                          ),
                          const Divider(height: 1),
                          IconButton(
                            tooltip: 'Zoom in',
                            icon: const Icon(Icons.add),
                            onPressed: () => _zoomBy(1.25),
                          ),
                          const Divider(height: 1),
                          IconButton(
                            tooltip: 'Zoom out',
                            icon: const Icon(Icons.remove),
                            onPressed: () => _zoomBy(0.8),
                          ),
                          const Divider(height: 1),
                          IconButton(
                            tooltip: 'Recenter',
                            icon: const Icon(
                              Icons.center_focus_strong_outlined,
                            ),
                            onPressed: () => _resetZoom(layout),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _ViewModeToggle(
                viewMode: viewMode,
                orientation: orientation,
                mode: mode,
                onSelected: _onViewOptionSelected,
                onModeChanged: _onModeChanged,
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

/// Vertical / Horizontal / List / Descendants, as a single pill row —
/// replaces both the old app-bar dropdown menu and the separate
/// Ancestors/Descendants toggle underneath it. "Ancestors" isn't its own
/// button: it's just whatever "Descendants" isn't (the default, unselected
/// state), since a vertical/horizontal ancestors view is the tree's normal
/// starting point — Descendants is the one alternate worth a dedicated
/// toggle.
/// A single floating card of stacked icon buttons docked over the canvas —
/// Search, Print, and zoom in/out/recenter all together, rather than two
/// separate cards.
class _CanvasActionCluster extends StatelessWidget {
  const _CanvasActionCluster({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.viewMode,
    required this.orientation,
    required this.mode,
    required this.onSelected,
    required this.onModeChanged,
  });

  final TreeViewMode viewMode;
  final TreeOrientation orientation;
  final TreeMode mode;
  final ValueChanged<_TreeViewOption> onSelected;
  final ValueChanged<TreeMode> onModeChanged;

  static const List<String> _labels = <String>[
    'Pedigree',
    'List',
    'Descendant',
  ];

  /// One font size shared by all three buttons, so a long label ("Descendant")
  /// never renders smaller than a short one ("List") just because each
  /// button used to scale its own text independently to fit its (equal)
  /// share of the row.
  double _sharedFontSize(BuildContext context, double maxWidth) {
    final TextStyle style =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);
    final double naturalSize = style.fontSize ?? 14;
    const int count = 3;
    const double spacing = AppSpacing.sm * (count - 1);
    const double hPadding = AppSpacing.sm * 2;
    final double perButtonWidth = (maxWidth - spacing) / count - hPadding;
    if (perButtonWidth <= 0) return naturalSize;

    double longest = 0;
    for (final String label in _labels) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width > longest) longest = painter.width;
    }
    if (longest <= 0) return naturalSize;

    final double scale = (perButtonWidth / longest).clamp(0.0, 1.0);
    return naturalSize * scale;
  }

  /// Vertical/Horizontal live inside a pull-up sheet from "Pedigree" now,
  /// rather than each getting their own button in the main row.
  void _showPedigreeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pedigree orientation',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Vertical'),
              trailing: orientation == TreeOrientation.vertical
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onSelected(_TreeViewOption.vertical);
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Horizontal'),
              trailing: orientation == TreeOrientation.horizontal
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                onSelected(_TreeViewOption.horizontal);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double fontSize = _sharedFontSize(
              context,
              constraints.maxWidth,
            );
            return Row(
              children: <Widget>[
                _ModeButton(
                  label: 'Pedigree',
                  fontSize: fontSize,
                  selected:
                      mode == TreeMode.ancestors &&
                      viewMode == TreeViewMode.graph,
                  onTap: () => _showPedigreeSheet(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                _ModeButton(
                  label: 'List',
                  fontSize: fontSize,
                  selected:
                      mode == TreeMode.ancestors &&
                      viewMode == TreeViewMode.list,
                  onTap: () => onSelected(_TreeViewOption.list),
                ),
                const SizedBox(width: AppSpacing.sm),
                _ModeButton(
                  label: 'Descendant',
                  fontSize: fontSize,
                  selected: mode == TreeMode.descendants,
                  onTap: () => onModeChanged(
                    mode == TreeMode.descendants
                        ? TreeMode.ancestors
                        : TreeMode.descendants,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.fontSize,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double fontSize;
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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? primary : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: selected ? primary : theme.dividerColor),
          ),
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: text.labelLarge?.copyWith(
              fontSize: fontSize,
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
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
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
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, style: text.bodySmall),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.textTertiary,
          ),
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
