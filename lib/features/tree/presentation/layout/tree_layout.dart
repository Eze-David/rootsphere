import 'dart:ui';

import '../../domain/entities/person.dart';

/// The viewing modes offered by the tree renderer.
enum TreeMode { ancestors, descendants }

/// Direction the ancestor pedigree grows: upward (vertical) or rightward
/// (horizontal). Chosen via the "view" control in the app bar.
enum TreeOrientation { vertical, horizontal }

/// Visual constants shared by the layout engine and the renderer.
class TreeMetrics {
  TreeMetrics._();

  static const double cardWidth = 116;
  static const double cardHeight = 150;
  static const double hGap = 28; // horizontal gap between sibling subtrees
  static const double spouseGap = 28; // gap between a couple's two cards
  static const double rowGap = 104; // vertical gap between generations
  static const double padding = 56; // outer padding around the whole tree

  static const double rowHeight = cardHeight + rowGap;

  /// Extra height reserved below the focus card for its inline "Add relative".
  static const double focusFooter = 52;
}

/// A person placed at an absolute position in scene coordinates.
class PositionedPerson {
  PositionedPerson({
    required this.person,
    required this.rect,
    this.isFocus = false,
    this.isSpouseCard = false,
  });

  final Person person;
  final Rect rect;
  final bool isFocus;

  /// True when this card is placed as somebody else's spouse rather than via
  /// the blood-line recursion — i.e. their own parents/other marriages are
  /// never walked into by the layout, so they may have relatives (in-laws)
  /// that this view doesn't show at all. Drives the "view their family"
  /// badge in the tree screen.
  final bool isSpouseCard;
}

/// A connector drawn between cards. [points] is a polyline (≥2 points).
class TreeConnector {
  TreeConnector({
    required this.points,
    this.isSpouse = false,
    this.roundCap = true,
  });

  final List<Offset> points;
  final bool isSpouse;

  /// Round line caps read fine on the tree's long elbow connectors, but on a
  /// very short stub (e.g. the spouse-family badge's link to its card) the
  /// rounded ends visually dominate the segment, making it look like a fat
  /// little pill instead of a thin line. Short stubs set this to false.
  final bool roundCap;

  Rect get bounds {
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Which missing parent an "Add" placeholder slot represents.
enum SlotKind { father, mother }

/// An empty "Add father / Add mother" slot placed where a parent is unknown.
class PositionedSlot {
  PositionedSlot({
    required this.rect,
    required this.childId,
    required this.kind,
  });

  final Rect rect;
  final String childId; // the person this slot would be a parent of
  final SlotKind kind;

  String get label => kind == SlotKind.father ? 'Add father' : 'Add mother';
}

/// A relationship caption shown between generations
/// (e.g. "Tradeda's grandparents"). [center] is the label's centre point.
class GenerationLabel {
  GenerationLabel({required this.text, required this.center});

  final String text;
  final Offset center;
}

/// A collapse/expand chevron sitting on the connector above [personId].
class CollapseToggle {
  CollapseToggle({
    required this.center,
    required this.personId,
    required this.collapsed,
  });

  final Offset center;
  final String personId;
  final bool collapsed;
}

/// The fully resolved layout ready for rendering.
class TreeLayout {
  TreeLayout({
    required this.nodes,
    required this.connectors,
    required this.size,
    required this.generations,
    required this.focusRect,
    this.slots = const <PositionedSlot>[],
    this.labels = const <GenerationLabel>[],
    this.toggles = const <CollapseToggle>[],
  });

  final List<PositionedPerson> nodes;
  final List<TreeConnector> connectors;
  final Size size;
  final int generations;
  final Rect focusRect;

  /// Empty "Add parent" slots (kinship view only).
  final List<PositionedSlot> slots;

  /// Per-generation relationship captions (kinship view only).
  final List<GenerationLabel> labels;

  /// Collapse/expand chevrons (kinship view only).
  final List<CollapseToggle> toggles;
}

/// Computes positions for persons + connectors for a given focus and mode.
///
/// Layout is a tidy top-down (descendants) or bottom-up (ancestors) tree using
/// post-order subtree centring. Spouses are paired beside the primary node and
/// children hang from the couple's midpoint. Pedigree composes both halves,
/// aligning the focus person horizontally.
class TreeLayoutEngine {
  static TreeLayout build({
    required List<Person> persons,
    required String focusId,
    required TreeMode mode,
    Set<String> collapsed = const <String>{},
    TreeOrientation orientation = TreeOrientation.vertical,
  }) {
    final byId = <String, Person>{for (final p in persons) p.id: p};
    final focus = byId[focusId] ?? persons.first;

    switch (mode) {
      case TreeMode.descendants:
        return _finalize(_Descendants(byId, collapsed).run(focus), focus.id);
      case TreeMode.ancestors:
        // The redesigned ancestor pedigree: focus + "Add father/mother" slots
        // and captions, growing upward (vertical) or rightward (horizontal).
        return _KinshipLayout(byId, collapsed, orientation).run(focus);
    }
  }

  // ── Normalisation: translate to positive space, build connectors ────────────
  static TreeLayout _finalize(_LayoutResult r, String focusId) {
    final byId = r.byId;

    // Assign y from generation (top-down).
    for (final n in r.allNodes) {
      n.y = n.gen * TreeMetrics.rowHeight;
    }

    if (r.allNodes.isEmpty) {
      return TreeLayout(
        nodes: const <PositionedPerson>[],
        connectors: const <TreeConnector>[],
        size: Size.zero,
        generations: 0,
        focusRect: Rect.zero,
      );
    }

    // Compute bounds.
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final n in r.allNodes) {
      minX = n.x < minX ? n.x : minX;
      minY = n.y < minY ? n.y : minY;
      final double rx = n.x + TreeMetrics.cardWidth;
      final double ry = n.y + TreeMetrics.cardHeight;
      maxX = rx > maxX ? rx : maxX;
      maxY = ry > maxY ? ry : maxY;
    }

    final double ox = TreeMetrics.padding - minX;
    final double oy = TreeMetrics.padding - minY;

    final positioned = <PositionedPerson>[];
    final rectById = <String, Rect>{};
    for (final n in r.allNodes) {
      final rect = Rect.fromLTWH(
        n.x + ox,
        n.y + oy,
        TreeMetrics.cardWidth,
        TreeMetrics.cardHeight,
      );
      rectById[n.id] = rect;
      positioned.add(
        PositionedPerson(
          person: byId[n.id]!,
          rect: rect,
          isFocus: n.id == focusId,
          isSpouseCard: n.isSpouse,
        ),
      );
    }

    final connectors = _buildConnectors(r, byId, rectById);

    final List<CollapseToggle> toggles = <CollapseToggle>[];
    for (final t in r.toggles) {
      final double parentBottom =
          t.gen * TreeMetrics.rowHeight + TreeMetrics.cardHeight + oy;
      toggles.add(CollapseToggle(
        center: Offset(t.x + ox, parentBottom + TreeMetrics.rowGap / 2),
        personId: t.personId,
        collapsed: t.collapsed,
      ));
    }
    final List<GenerationLabel> labels =
        _buildDescendantLabels(r, byId[focusId]!, rectById);

    final Size size = Size(
      maxX - minX + TreeMetrics.padding * 2,
      maxY - minY + TreeMetrics.padding * 2,
    );

    final int generations =
        r.allNodes.map((n) => n.gen).fold<int>(0, (a, b) => a > b ? a : b) + 1;

    return TreeLayout(
      nodes: positioned,
      connectors: connectors,
      labels: labels,
      toggles: toggles,
      size: size,
      generations: generations,
      focusRect: rectById[focusId] ?? Rect.zero,
    );
  }

  /// One caption per descendant generation (e.g. "Tradeda's children",
  /// "Tradeda's grandchildren"), centred above that generation's row —
  /// mirrors `_KinshipLayout._buildLabels` for the ancestor pedigree.
  static List<GenerationLabel> _buildDescendantLabels(
    _LayoutResult r,
    Person focus,
    Map<String, Rect> rectById,
  ) {
    final List<GenerationLabel> out = <GenerationLabel>[];
    final int maxGen =
        r.allNodes.fold<int>(0, (a, n) => n.gen > a ? n.gen : a);
    for (int g = 1; g <= maxGen; g++) {
      final List<Rect> rects = r.allNodes
          .where((n) => n.gen == g)
          .map((n) => rectById[n.id]!)
          .toList();
      if (rects.isEmpty) continue;
      double minL = double.infinity, maxR = -double.infinity;
      double minT = double.infinity;
      for (final rr in rects) {
        if (rr.left < minL) minL = rr.left;
        if (rr.right > maxR) maxR = rr.right;
        if (rr.top < minT) minT = rr.top;
      }
      final String text = "${focus.givenName}'s ${_descendantRelationName(g)}";
      out.add(GenerationLabel(
        text: text,
        center: Offset((minL + maxR) / 2, minT - 16),
      ));
    }
    return out;
  }

  static String _descendantRelationName(int gen) {
    if (gen == 1) return 'children';
    if (gen == 2) return 'grandchildren';
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < gen - 2; i++) {
      b.write('great-');
    }
    b.write('grandchildren');
    return b.toString();
  }

  /// Builds spouse + parent-child elbow connectors from the placed rects.
  static List<TreeConnector> _buildConnectors(
    _LayoutResult r,
    Map<String, Person> byId,
    Map<String, Rect> rectById,
  ) {
    final connectors = <TreeConnector>[];
    final placed = rectById.keys.toSet();

    // Spouse connectors (draw once per pair).
    final drawnPairs = <String>{};
    for (final id in placed) {
      final p = byId[id]!;
      for (final sId in p.spouseIds) {
        if (!placed.contains(sId)) continue;
        final key = (id.compareTo(sId) < 0) ? '$id|$sId' : '$sId|$id';
        if (drawnPairs.contains(key)) continue;
        drawnPairs.add(key);
        final a = rectById[id]!;
        final b = rectById[sId]!;
        // Only connect if roughly on the same row.
        if ((a.top - b.top).abs() > 1) continue;
        final left = a.left < b.left ? a : b;
        final right = a.left < b.left ? b : a;
        connectors.add(
          TreeConnector(
            points: <Offset>[
              Offset(left.right, left.center.dy),
              Offset(right.left, right.center.dy),
            ],
            isSpouse: true,
          ),
        );
      }
    }

    // Parent-child connectors: from couple midpoint to each child.
    // Group children by their parent set's couple-centre.
    for (final childId in placed) {
      final child = byId[childId]!;
      final parents = child.parentIds.where(placed.contains).toList();
      if (parents.isEmpty) continue;
      final childRect = rectById[childId]!;

      // Couple centre = midpoint of placed parents' rects.
      double cx = 0;
      double parentBottom = -double.infinity;
      for (final pid in parents) {
        final pr = rectById[pid]!;
        cx += pr.center.dx;
        parentBottom = pr.bottom > parentBottom ? pr.bottom : parentBottom;
      }
      cx /= parents.length;

      final bool childIsBelow = childRect.top > parentBottom;
      if (childIsBelow) {
        final double busY = parentBottom + TreeMetrics.rowGap / 2;
        connectors.add(
          TreeConnector(
            points: <Offset>[
              Offset(cx, parentBottom),
              Offset(cx, busY),
              Offset(childRect.center.dx, busY),
              Offset(childRect.center.dx, childRect.top),
            ],
          ),
        );
      } else {
        // Ancestors view: child sits below its parents (parents above child).
        final double childTop = childRect.top;
        final double busY = childTop - TreeMetrics.rowGap / 2;
        connectors.add(
          TreeConnector(
            points: <Offset>[
              Offset(childRect.center.dx, childTop),
              Offset(childRect.center.dx, busY),
              Offset(cx, busY),
              Offset(cx, parentBottom > childTop ? childTop : parentBottom),
            ],
          ),
        );
      }
    }

    return connectors;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal mutable node + per-direction layouters
// ─────────────────────────────────────────────────────────────────────────────

class _Node {
  _Node(this.id, this.gen, this.x, {this.isSpouse = false});
  final String id;
  final int gen;
  double x;
  double y = 0;

  /// True when placed via [_Descendants._spouseOf] rather than the blood-line
  /// recursion — see [PositionedPerson.isSpouseCard].
  final bool isSpouse;
}

/// A pending collapse toggle for a person's children row, recorded in raw
/// (pre-offset) layout coordinates; [TreeLayoutEngine._finalize] converts it
/// into a final [CollapseToggle] once the whole tree's offset is known.
class _PendingToggle {
  _PendingToggle({
    required this.personId,
    required this.gen,
    required this.x,
    required this.collapsed,
  });

  final String personId;
  final int gen; // generation of the parent; children sit at gen + 1
  final double x; // raw centre x of the parent's own card (not the couple)
  final bool collapsed;
}

class _LayoutResult {
  _LayoutResult(this.byId);
  final Map<String, Person> byId;
  final List<_Node> allNodes = <_Node>[];
  final List<_PendingToggle> toggles = <_PendingToggle>[];

  void add(_Node n) => allNodes.add(n);
}

/// Top-down layout: focus at gen 0, children below. Pairs spouses.
///
/// A person in [collapsed] is still drawn but their own children are hidden
/// (and not recursed into); a [CollapseToggle] is still emitted for them so
/// the branch can be re-expanded, mirroring `_KinshipLayout`'s ancestor
/// collapsing.
class _Descendants {
  _Descendants(this.byId, this.collapsed);
  final Map<String, Person> byId;
  final Set<String> collapsed;
  final _LayoutResult result = _LayoutResult(<String, Person>{});
  double _cursor = 0;
  final Set<String> _visited = <String>{};

  _LayoutResult run(Person focus) {
    result.byId.addAll(byId);
    _layout(focus, 0);
    return result;
  }

  List<Person> _childrenOf(Person p) {
    return byId.values
        .where((c) => c.parentIds.contains(p.id))
        .toList()
      ..sort((a, b) => (a.birthDate?.year ?? 0).compareTo(b.birthDate?.year ?? 0));
  }

  Person? _spouseOf(Person p) {
    for (final s in p.spouseIds) {
      if (byId.containsKey(s) && !_visited.contains(s)) return byId[s];
    }
    return null;
  }

  /// Returns the couple centre x of [person] at [gen].
  double _layout(Person person, int gen) {
    if (_visited.contains(person.id)) {
      // Already placed; return its centre.
      final existing = result.allNodes.firstWhere((n) => n.id == person.id);
      return existing.x + TreeMetrics.cardWidth / 2;
    }
    _visited.add(person.id);

    final spouse = _spouseOf(person);
    final allChildren = _childrenOf(person);
    final bool isCollapsed = collapsed.contains(person.id);
    final List<Person> children = isCollapsed ? const <Person>[] : allChildren;

    final double coupleSpan = spouse != null
        ? TreeMetrics.cardWidth * 2 + TreeMetrics.spouseGap
        : TreeMetrics.cardWidth;

    double centre;
    double left;
    if (children.isEmpty) {
      left = _cursor;
      centre = left + coupleSpan / 2;
      _place(person, gen, left);
      if (spouse != null) {
        _visited.add(spouse.id);
        _place(
          spouse,
          gen,
          left + TreeMetrics.cardWidth + TreeMetrics.spouseGap,
          isSpouse: true,
        );
      }
      _cursor = left + coupleSpan + TreeMetrics.hGap;
    } else {
      // Record where this subtree's nodes begin so we can shift the whole
      // subtree as a unit if the couple needs more room than the children span.
      final int subtreeStart = result.allNodes.length;
      final childCentres = <double>[];
      for (final c in children) {
        childCentres.add(_layout(c, gen + 1));
      }
      centre = (childCentres.first + childCentres.last) / 2;
      left = centre - coupleSpan / 2;
      // If the centred couple would overlap an earlier subtree, shift the
      // *entire* child subtree right by the deficit so the parent stays
      // centred over its children (proper tidy-tree behaviour) rather than
      // de-centring the parent.
      if (left < _cursor) {
        final double delta = _cursor - left;
        for (int i = subtreeStart; i < result.allNodes.length; i++) {
          result.allNodes[i].x += delta;
        }
        for (int i = 0; i < childCentres.length; i++) {
          childCentres[i] += delta;
        }
        centre = (childCentres.first + childCentres.last) / 2;
        left = centre - coupleSpan / 2;
      }
      _place(person, gen, left);
      if (spouse != null) {
        _visited.add(spouse.id);
        _place(
          spouse,
          gen,
          left + TreeMetrics.cardWidth + TreeMetrics.spouseGap,
          isSpouse: true,
        );
      }
      final double right = left + coupleSpan;
      if (right + TreeMetrics.hGap > _cursor) {
        _cursor = right + TreeMetrics.hGap;
      }
    }

    if (allChildren.isNotEmpty) {
      result.toggles.add(_PendingToggle(
        personId: person.id,
        gen: gen,
        x: left + TreeMetrics.cardWidth / 2,
        collapsed: isCollapsed,
      ));
    }

    return centre;
  }

  void _place(Person p, int gen, double x, {bool isSpouse = false}) =>
      result.add(_Node(p.id, gen, x, isSpouse: isSpouse));
}

// ─────────────────────────────────────────────────────────────────────────────
// Kinship pedigree: focus at the bottom, ancestors upward, with empty
// "Add father / Add mother" slots wherever a parent is unknown. Real people
// recurse upward; placeholder slots are leaves (so the layout terminates).
// Each real person can be collapsed to hide its ancestors.
// ─────────────────────────────────────────────────────────────────────────────

class _PlacedKinNode {
  _PlacedKinNode({
    required this.key,
    required this.gen,
    required this.x,
    this.personId,
    this.childId,
    this.kind,
    this.isFocusExtra = false,
  });

  final String key;
  final int gen;
  double x;
  double y = 0;
  final String? personId; // null ⇒ placeholder slot
  final String? childId; // placeholder's child
  final SlotKind? kind; // placeholder kind

  /// True for the focus's spouse/children — placed alongside the ancestor
  /// pedigree but not themselves recursed into, so they don't get an
  /// ancestor-collapse toggle of their own.
  final bool isFocusExtra;

  bool get isSlot => personId == null;
}

class _KinshipLayout {
  _KinshipLayout(this.byId, this.collapsed, this.orientation);

  final Map<String, Person> byId;
  final Set<String> collapsed;
  final TreeOrientation orientation;

  final List<_PlacedKinNode> _nodes = <_PlacedKinNode>[];
  final Map<String, _PlacedKinNode> _byKey = <String, _PlacedKinNode>{};
  final Map<String, List<String>> _parentKeysOf = <String, List<String>>{};
  final Set<String> _visited = <String>{};
  int _maxGen = 0;

  // The focus's spouse/children ("hourglass waist" below the pedigree — see
  // `_placeFocusFamily`), tracked separately since they're not part of the
  // ancestor recursion.
  String? _focusSpouseKey;
  final List<String> _focusChildKeys = <String>[];
  double? _focusFamilyCentre; // raw breadth-centre of the couple
  bool _focusChildrenCollapsed = false;

  bool get _horizontal => orientation == TreeOrientation.horizontal;

  // Card dimensions + spacing differ per orientation. "breadth" is the
  // cross-generation axis (siblings spread along it); "depth" is the
  // generation axis.
  double get _cardW => _horizontal ? 212 : 116;
  double get _cardH => _horizontal ? 64 : 150;
  double get _breadthExtent => _horizontal ? _cardH : _cardW;
  double get _crossGap => _horizontal ? 8 : 4;
  double get _depthGap => _horizontal ? 84 : 104;
  double get _spouseGap => _horizontal ? 14 : TreeMetrics.spouseGap;

  /// Gap between the focus's own row and their children row — deliberately
  /// larger than [_depthGap] (used for the ancestor generations above) so the
  /// children row/toggle/caption don't feel cramped against the focus card.
  double get _childDepthGap => _horizontal ? 112 : 140;

  /// Stable key for a person's children-collapse state, namespaced separately
  /// from their (plain-id-keyed) ancestor-collapse state in the same [collapsed]
  /// set — collapsing one direction shouldn't collapse the other.
  static String childrenToggleKey(String personId) => 'children:$personId';

  /// Extra space reserved below the focus card for its inline "Add relative".
  static const double focusExtra = TreeMetrics.focusFooter;

  static String _slotKey(String childId, SlotKind k) =>
      'slot:$childId:${k.name}';

  void _add(_PlacedKinNode n) {
    _nodes.add(n);
    _byKey[n.key] = n;
  }

  /// Resolves the (father, mother) pair for [id] from its known parents —
  /// by sex first, then by remaining order — leaving either/both null where
  /// unknown. Shared by [_subtreeWidth] and [_placeReal], which must agree
  /// on the same resolution.
  (String?, String?) _resolveParents(String id) {
    final Person p = byId[id]!;
    final List<String> remaining =
        p.parentIds.where(byId.containsKey).toList();
    String? father = _firstWhere(remaining, (x) => byId[x]!.sex == Sex.male);
    if (father != null) remaining.remove(father);
    String? mother = _firstWhere(remaining, (x) => byId[x]!.sex == Sex.female);
    if (mother != null) remaining.remove(mother);
    if (father == null && remaining.isNotEmpty) father = remaining.removeAt(0);
    if (mother == null && remaining.isNotEmpty) mother = remaining.removeAt(0);
    return (father, mother);
  }

  final Map<String, double> _widthCache = <String, double>{};

  /// The total breadth [id]'s own ancestor fan needs — i.e. how much room
  /// to reserve so it never collides with a cousin branch. A couple (a real
  /// person plus their known father/mother, real or placeholder) always
  /// needs `fatherWidth + spouseGap + motherWidth`; that same spouseGap is
  /// what keeps every direct couple in the pedigree exactly as tight as the
  /// focus's own spouse, however deep either side's own ancestry goes — see
  /// [_placeReal].
  double _subtreeWidth(String id) {
    final double? cached = _widthCache[id];
    if (cached != null) return cached;
    double width;
    if (collapsed.contains(id)) {
      width = _breadthExtent;
    } else {
      final (String? father, String? mother) = _resolveParents(id);
      final double fatherW =
          father != null ? _subtreeWidth(father) : _breadthExtent;
      final double motherW =
          mother != null ? _subtreeWidth(mother) : _breadthExtent;
      width = fatherW + _spouseGap + motherW;
    }
    _widthCache[id] = width;
    return width;
  }

  /// Places real [id] (and its ancestors) within the breadth range
  /// `[rangeLeft, rangeLeft + _subtreeWidth(id))` reserved for it by the
  /// caller. [cardOnRight] puts id's own card at the range's right edge
  /// (used for the father side of a couple, so his own ancestors fan
  /// further left, away from the mother) or left edge (the mother side,
  /// fanning right) — whichever side keeps id's card adjacent to its
  /// spouse. Every direct couple ends up exactly `spouseGap` apart this
  /// way, regardless of how much deeper either side's own ancestry goes,
  /// rather than each of them drifting to the centre of their own
  /// (possibly much wider) subtree.
  void _placeReal(String id, int gen, double rangeLeft, bool cardOnRight) {
    if (_visited.contains(id)) return;
    _visited.add(id);
    if (gen > _maxGen) _maxGen = gen;

    final double width = _subtreeWidth(id);
    final double left =
        cardOnRight ? rangeLeft + width - _breadthExtent : rangeLeft;
    _add(_PlacedKinNode(key: id, gen: gen, x: left, personId: id));

    if (collapsed.contains(id)) return;

    final (String? father, String? mother) = _resolveParents(id);
    final String fatherKey = father ?? _slotKey(id, SlotKind.father);
    final String motherKey = mother ?? _slotKey(id, SlotKind.mother);
    final double fatherW =
        father != null ? _subtreeWidth(father) : _breadthExtent;
    final double motherRangeLeft = rangeLeft + fatherW + _spouseGap;

    if (father != null) {
      _placeReal(father, gen + 1, rangeLeft, true);
    } else {
      _placeSlotAt(id, SlotKind.father, gen + 1, rangeLeft + fatherW - _breadthExtent);
    }
    if (mother != null) {
      _placeReal(mother, gen + 1, motherRangeLeft, false);
    } else {
      _placeSlotAt(id, SlotKind.mother, gen + 1, motherRangeLeft);
    }
    _parentKeysOf[id] = <String>[fatherKey, motherKey];
  }

  /// Places the pedigree's root (the focus person) — unlike [_placeReal],
  /// centred over its own two parents rather than edge-anchored, since the
  /// root has no sibling couple of its own to stay tight with (that's what
  /// [_placeFocusFamily] handles, separately, for the focus's spouse). Its
  /// own father/mother are still placed via the same tight edge-anchored
  /// scheme relative to each other.
  void _placeRoot(String id, int gen) {
    _visited.add(id);
    if (gen > _maxGen) _maxGen = gen;

    if (collapsed.contains(id)) {
      _add(_PlacedKinNode(key: id, gen: gen, x: 0, personId: id));
      return;
    }

    final (String? father, String? mother) = _resolveParents(id);
    final String fatherKey = father ?? _slotKey(id, SlotKind.father);
    final String motherKey = mother ?? _slotKey(id, SlotKind.mother);
    final double fatherW =
        father != null ? _subtreeWidth(father) : _breadthExtent;
    final double motherRangeLeft = fatherW + _spouseGap;

    if (father != null) {
      _placeReal(father, gen + 1, 0, true);
    } else {
      _placeSlotAt(id, SlotKind.father, gen + 1, fatherW - _breadthExtent);
    }
    if (mother != null) {
      _placeReal(mother, gen + 1, motherRangeLeft, false);
    } else {
      _placeSlotAt(id, SlotKind.mother, gen + 1, motherRangeLeft);
    }

    final double fatherCentre = _byKey[fatherKey]!.x + _breadthExtent / 2;
    final double motherCentre = _byKey[motherKey]!.x + _breadthExtent / 2;
    final double centre = (fatherCentre + motherCentre) / 2;
    _add(
      _PlacedKinNode(key: id, gen: gen, x: centre - _breadthExtent / 2, personId: id),
    );
    _parentKeysOf[id] = <String>[fatherKey, motherKey];
  }

  void _placeSlotAt(String childId, SlotKind kind, int gen, double x) {
    if (gen > _maxGen) _maxGen = gen;
    _add(_PlacedKinNode(
      key: _slotKey(childId, kind),
      gen: gen,
      x: x,
      childId: childId,
      kind: kind,
    ));
  }

  /// Places the focus's spouse (beside) and immediate children (below, via a
  /// collapsible "`Focus`'s children" row) — the pedigree's "hourglass waist".
  /// Unlike ancestors, children are leaves here (no grandchildren): this
  /// mirrors a traditional pedigree chart's treatment of the base person,
  /// it isn't a full descendants tree.
  void _placeFocusFamily(Person focus) {
    final _PlacedKinNode focusNode = _byKey[focus.id]!;
    double coupleLeft = focusNode.x;
    double coupleRight = focusNode.x + _breadthExtent;

    Person? spouse;
    for (final sId in focus.spouseIds) {
      final Person? s = byId[sId];
      if (s != null && !_visited.contains(sId)) {
        spouse = s;
        break;
      }
    }
    if (spouse != null) {
      _visited.add(spouse.id);
      // Male always ends up first along the breadth axis (left in vertical
      // orientation, top in horizontal) and the other partner second,
      // regardless of which of the two is currently the tree's focus — so
      // re-rooting onto a spouse (via the "view their family" badge) never
      // flips the couple's positions relative to each other.
      final bool spouseGoesFirst =
          spouse.sex == Sex.male && focus.sex != Sex.male;
      final double sx = spouseGoesFirst
          ? focusNode.x - _spouseGap - _breadthExtent
          : coupleRight + _spouseGap;
      _add(_PlacedKinNode(key: spouse.id, gen: 0, x: sx, personId: spouse.id, isFocusExtra: true));
      _focusSpouseKey = spouse.id;
      coupleLeft = spouseGoesFirst ? sx : coupleLeft;
      coupleRight = spouseGoesFirst ? coupleRight : sx + _breadthExtent;
    }
    _focusFamilyCentre = (coupleLeft + coupleRight) / 2;

    final List<Person> children = byId.values
        .where((c) => c.parentIds.contains(focus.id) && !_visited.contains(c.id))
        .toList()
      ..sort((a, b) => (a.birthDate?.year ?? 0).compareTo(b.birthDate?.year ?? 0));
    if (children.isEmpty) return;

    _focusChildrenCollapsed = collapsed.contains(childrenToggleKey(focus.id));
    if (_focusChildrenCollapsed) return;

    final double totalWidth =
        children.length * _breadthExtent + (children.length - 1) * _crossGap;
    double left = _focusFamilyCentre! - totalWidth / 2;
    for (final child in children) {
      _visited.add(child.id);
      _add(_PlacedKinNode(key: child.id, gen: -1, x: left, personId: child.id, isFocusExtra: true));
      _focusChildKeys.add(child.id);
      left += _breadthExtent + _crossGap;
    }
  }

  /// Spouse + parent-child connectors for the focus's family (see
  /// [_placeFocusFamily]) — separate from [_buildKinConnectors], which only
  /// handles the ancestor pedigree.
  List<TreeConnector> _buildFocusFamilyConnectors(
    String focusId,
    Map<String, Rect> rectByKey,
  ) {
    final List<TreeConnector> out = <TreeConnector>[];
    final Rect? focusRect = rectByKey[focusId];
    if (focusRect == null) return out;

    final Rect? spouseRect =
        _focusSpouseKey == null ? null : rectByKey[_focusSpouseKey];
    if (spouseRect != null) {
      // Whichever of the two is actually first along the breadth axis (not
      // necessarily the focus — see _placeFocusFamily's male-first rule),
      // draw from its trailing edge to the other's leading edge.
      final bool focusFirst = _horizontal
          ? focusRect.top <= spouseRect.top
          : focusRect.left <= spouseRect.left;
      final Rect first = focusFirst ? focusRect : spouseRect;
      final Rect second = focusFirst ? spouseRect : focusRect;
      out.add(TreeConnector(
        points: _horizontal
            ? <Offset>[
                Offset(first.center.dx, first.bottom),
                Offset(second.center.dx, second.top),
              ]
            : <Offset>[
                Offset(first.right, first.center.dy),
                Offset(second.left, second.center.dy),
              ],
        isSpouse: true,
      ));
    }

    final List<Rect> childRects =
        _focusChildKeys.map((k) => rectByKey[k]!).toList();
    if (childRects.isEmpty) return out;

    if (_horizontal) {
      final double cy = spouseRect != null
          ? (focusRect.center.dy + spouseRect.center.dy) / 2
          : focusRect.center.dy;
      final double parentLeft = spouseRect != null
          ? (focusRect.left < spouseRect.left ? focusRect.left : spouseRect.left)
          : focusRect.left;
      final double busX = parentLeft - _childDepthGap / 2;
      // When there's a spouse, the spouse connector is drawn at the card's
      // horizontal centre (`center.dx`), not its edge (`parentLeft`) — start
      // here too so the two lines actually meet instead of leaving a gap
      // across the width of the card. Without a spouse there's no such line
      // to meet, so start from the edge as before.
      final double startX = spouseRect != null ? focusRect.center.dx : parentLeft;
      for (final cr in childRects) {
        out.add(TreeConnector(points: <Offset>[
          Offset(startX, cy),
          Offset(busX, cy),
          Offset(busX, cr.center.dy),
          Offset(cr.right, cr.center.dy),
        ]));
      }
    } else {
      final double cx = spouseRect != null
          ? (focusRect.center.dx + spouseRect.center.dx) / 2
          : focusRect.center.dx;
      final double parentBottom = spouseRect != null
          ? (focusRect.bottom > spouseRect.bottom ? focusRect.bottom : spouseRect.bottom)
          : focusRect.bottom;
      final double busY = parentBottom + _childDepthGap / 2;
      // When there's a spouse, `cx` falls in the empty gap between the two
      // cards (not under either), so starting the line at the row's centre
      // height — where the spouse connector sits — closes what would
      // otherwise be a visible gap between it and the child's line. Without a
      // spouse, `cx` is under the focus card itself, so it doesn't matter
      // (that segment is hidden behind the card either way).
      final double startY = spouseRect != null ? focusRect.center.dy : parentBottom;
      for (final cr in childRects) {
        out.add(TreeConnector(points: <Offset>[
          Offset(cx, startY),
          Offset(cx, busY),
          Offset(cr.center.dx, busY),
          Offset(cr.center.dx, cr.top),
        ]));
      }
    }
    return out;
  }

  /// Maps a node's breadth (`x`) + generation into an absolute, un-offset rect.
  Rect _rawRect(_PlacedKinNode n) {
    if (_horizontal) {
      // Focus on the left, ancestors grow to the right. The children row
      // (gen -1) uses its own, larger gap instead of the uniform per-gen
      // formula, so it doesn't inherit the ancestors' (tighter) spacing.
      final double left = n.gen < 0
          ? -(_cardW + _childDepthGap)
          : n.gen * (_cardW + _depthGap);
      return Rect.fromLTWH(left, n.x, _cardW, _cardH);
    }
    // Focus at the bottom, ancestors grow upward. The children row (gen -1)
    // sits just below the focus's own row (gen 0), using its own gap.
    final double gen0Top = _maxGen * (_cardH + _depthGap);
    final double top = n.gen < 0
        ? gen0Top + _cardH + _childDepthGap
        : (_maxGen - n.gen) * (_cardH + _depthGap);
    return Rect.fromLTWH(n.x, top, _cardW, _cardH);
  }

  TreeLayout run(Person focus) {
    if (byId.isEmpty) {
      return TreeLayout(
        nodes: const <PositionedPerson>[],
        connectors: const <TreeConnector>[],
        size: Size.zero,
        generations: 0,
        focusRect: Rect.zero,
      );
    }

    _placeRoot(focus.id, 0);
    _placeFocusFamily(focus);

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    final Map<String, Rect> rawByKey = <String, Rect>{};
    for (final n in _nodes) {
      final Rect r = _rawRect(n);
      rawByKey[n.key] = r;
      minX = r.left < minX ? r.left : minX;
      minY = r.top < minY ? r.top : minY;
      maxX = r.right > maxX ? r.right : maxX;
      maxY = r.bottom > maxY ? r.bottom : maxY;
    }

    final double ox = TreeMetrics.padding - minX;
    final double oy = TreeMetrics.padding - minY;

    final List<PositionedPerson> persons = <PositionedPerson>[];
    final List<PositionedSlot> slots = <PositionedSlot>[];
    final List<CollapseToggle> toggles = <CollapseToggle>[];
    final Map<String, Rect> rectByKey = <String, Rect>{};

    for (final n in _nodes) {
      final Rect raw = rawByKey[n.key]!;
      final Rect rect = raw.shift(Offset(ox, oy));
      rectByKey[n.key] = rect;
      if (n.isSlot) {
        slots.add(PositionedSlot(
          rect: rect,
          childId: n.childId!,
          kind: n.kind!,
        ));
      } else {
        persons.add(PositionedPerson(
          person: byId[n.personId]!,
          rect: rect,
          isFocus: n.personId == focus.id,
          isSpouseCard: n.key == _focusSpouseKey,
        ));
        // The chevron sits on the connector toward this person's parents.
        // The focus's spouse/children aren't recursed into, so they don't
        // get one of these (they get the children-toggle below instead).
        if (!n.isFocusExtra) {
          final Offset tc = _horizontal
              ? Offset(rect.right + _depthGap / 2, rect.center.dy)
              : Offset(rect.center.dx, rect.top - _depthGap / 2);
          toggles.add(CollapseToggle(
            center: tc,
            personId: n.personId!,
            collapsed: collapsed.contains(n.personId),
          ));
        }
      }
    }

    final List<TreeConnector> connectors = <TreeConnector>[
      ..._buildKinConnectors(rectByKey),
      ..._buildFocusFamilyConnectors(focus.id, rectByKey),
    ];
    final List<GenerationLabel> labels = _buildLabels(focus, rectByKey);

    // The focus's children row + its collapse toggle (see _placeFocusFamily).
    final double? familyCentre = _focusFamilyCentre;
    if (familyCentre != null && (_focusChildKeys.isNotEmpty || _focusChildrenCollapsed)) {
      final double toggleDepth = _horizontal
          ? -_childDepthGap / 2
          : _maxGen * (_cardH + _depthGap) + _cardH + _childDepthGap / 2;
      final Offset rawCentre = _horizontal
          ? Offset(toggleDepth, familyCentre)
          : Offset(familyCentre, toggleDepth);
      toggles.add(CollapseToggle(
        center: rawCentre + Offset(ox, oy),
        personId: childrenToggleKey(focus.id),
        collapsed: _focusChildrenCollapsed,
      ));

      if (_focusChildKeys.isNotEmpty) {
        final List<Rect> childRects =
            _focusChildKeys.map((k) => rectByKey[k]!).toList();
        double minL = double.infinity, maxR = -double.infinity;
        double minT = double.infinity;
        for (final r in childRects) {
          if (r.left < minL) minL = r.left;
          if (r.right > maxR) maxR = r.right;
          if (r.top < minT) minT = r.top;
        }
        labels.add(GenerationLabel(
          text: "${focus.givenName}'s children",
          center: Offset((minL + maxR) / 2, minT - 16),
        ));
      }
    }

    final Size size = Size(
      maxX - minX + TreeMetrics.padding * 2,
      maxY - minY + TreeMetrics.padding * 2 + focusExtra,
    );

    return TreeLayout(
      nodes: persons,
      connectors: connectors,
      slots: slots,
      labels: labels,
      toggles: toggles,
      size: size,
      generations: _maxGen + 1,
      focusRect: rectByKey[focus.id] ?? Rect.zero,
    );
  }

  List<TreeConnector> _buildKinConnectors(Map<String, Rect> rectByKey) {
    final List<TreeConnector> out = <TreeConnector>[];
    _parentKeysOf.forEach((childKey, parentKeys) {
      final Rect? childRect = rectByKey[childKey];
      if (childRect == null) return;
      for (final pk in parentKeys) {
        final Rect? pr = rectByKey[pk];
        if (pr == null) continue;
        if (_horizontal) {
          // Child's right → bus → parent's left.
          final double busX = childRect.right + _depthGap / 2;
          out.add(TreeConnector(points: <Offset>[
            Offset(childRect.right, childRect.center.dy),
            Offset(busX, childRect.center.dy),
            Offset(busX, pr.center.dy),
            Offset(pr.left, pr.center.dy),
          ]));
        } else {
          // Child's top → bus → parent's bottom.
          final double busY = childRect.top - _depthGap / 2;
          out.add(TreeConnector(points: <Offset>[
            Offset(childRect.center.dx, childRect.top),
            Offset(childRect.center.dx, busY),
            Offset(pr.center.dx, busY),
            Offset(pr.center.dx, pr.bottom),
          ]));
        }
      }
    });
    return out;
  }

  List<GenerationLabel> _buildLabels(
    Person focus,
    Map<String, Rect> rectByKey,
  ) {
    final List<GenerationLabel> out = <GenerationLabel>[];
    for (int g = 1; g <= _maxGen; g++) {
      final List<Rect> rects = _nodes
          .where((n) => n.gen == g)
          .map((n) => rectByKey[n.key]!)
          .toList();
      if (rects.isEmpty) continue;
      double minL = double.infinity, maxR = -double.infinity;
      double minT = double.infinity, maxB = -double.infinity;
      for (final r in rects) {
        if (r.left < minL) minL = r.left;
        if (r.right > maxR) maxR = r.right;
        if (r.top < minT) minT = r.top;
        if (r.bottom > maxB) maxB = r.bottom;
      }
      final String text = "${focus.givenName}'s ${_relationName(g)}";
      final Offset center = _horizontal
          // Above the generation's column.
          ? Offset((minL + maxR) / 2, minT - 16)
          // Just below the generation's row (toward the focus).
          : Offset((minL + maxR) / 2, maxB + 16);
      out.add(GenerationLabel(text: text, center: center));
    }
    return out;
  }

  static String _relationName(int gen) {
    if (gen == 1) return 'parents';
    if (gen == 2) return 'grandparents';
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < gen - 2; i++) {
      b.write('great-');
    }
    b.write('grandparents');
    return b.toString();
  }

  static String? _firstWhere(List<String> xs, bool Function(String) test) {
    for (final x in xs) {
      if (test(x)) return x;
    }
    return null;
  }
}
