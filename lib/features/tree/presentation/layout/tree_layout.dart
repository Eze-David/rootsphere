import 'dart:ui';

import '../../domain/entities/person.dart';

/// The three viewing modes from the Phase 2 brief / mockups.
enum TreeMode { ancestors, descendants, pedigree }

/// Visual constants shared by the layout engine and the renderer.
class TreeMetrics {
  TreeMetrics._();

  static const double cardWidth = 150;
  static const double cardHeight = 64;
  static const double hGap = 28; // horizontal gap between sibling subtrees
  static const double spouseGap = 16; // gap between a couple's two cards
  static const double rowGap = 56; // vertical gap between generations
  static const double padding = 48; // outer padding around the whole tree

  static const double rowHeight = cardHeight + rowGap;
}

/// A person placed at an absolute position in scene coordinates.
class PositionedPerson {
  PositionedPerson({
    required this.person,
    required this.rect,
    this.isFocus = false,
  });

  final Person person;
  final Rect rect;
  final bool isFocus;
}

/// A connector drawn between cards. [points] is a polyline (≥2 points).
class TreeConnector {
  TreeConnector({required this.points, this.isSpouse = false});

  final List<Offset> points;
  final bool isSpouse;

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

/// The fully resolved layout ready for rendering.
class TreeLayout {
  TreeLayout({
    required this.nodes,
    required this.connectors,
    required this.size,
    required this.generations,
    required this.focusRect,
  });

  final List<PositionedPerson> nodes;
  final List<TreeConnector> connectors;
  final Size size;
  final int generations;
  final Rect focusRect;
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
  }) {
    final byId = <String, Person>{for (final p in persons) p.id: p};
    final focus = byId[focusId] ?? persons.first;

    switch (mode) {
      case TreeMode.descendants:
        return _finalize(_Descendants(byId).run(focus), focus.id);
      case TreeMode.ancestors:
        return _finalize(_Ancestors(byId).run(focus), focus.id, flipY: true);
      case TreeMode.pedigree:
        return _pedigree(byId, focus);
    }
  }

  // ── Pedigree: ancestors above + descendants below, focus aligned ────────────
  static TreeLayout _pedigree(Map<String, Person> byId, Person focus) {
    final desc = _Descendants(byId).run(focus); // focus at gen 0, down
    final anc = _Ancestors(byId).run(focus); // focus at gen 0, up

    // Both place focus; align their focus x, then merge (skip anc's focus).
    final descFocus = desc.nodesByGen[0]!.firstWhere((n) => n.id == focus.id);
    final ancFocus = anc.nodesByGen[0]!.firstWhere((n) => n.id == focus.id);
    final double dx = ancFocus.x - descFocus.x;

    final List<_Node> all = <_Node>[];
    // Ancestors above (gen > 0 rendered upward) + the shared focus.
    for (final n in anc.allNodes) {
      all.add(n.copy(y: -n.gen * TreeMetrics.rowHeight));
    }
    // Descendants below (gen > 0), shifted to align focus.
    for (final n in desc.allNodes) {
      if (n.gen == 0) continue; // focus already added from anc
      all.add(n.copy(x: n.x + dx, y: n.gen * TreeMetrics.rowHeight));
    }

    final result = _LayoutResult(byId);
    result.allNodes.addAll(all);
    final int gens = anc.maxGen + desc.maxGen + 1;
    return _finalize(result, focus.id, gens: gens, alreadyHasY: true);
  }

  // ── Normalisation: translate to positive space, build connectors ────────────
  static TreeLayout _finalize(
    _LayoutResult r,
    String focusId, {
    bool flipY = false,
    int? gens,
    bool alreadyHasY = false,
  }) {
    final byId = r.byId;

    // Assign y from gen if not already done.
    for (final n in r.allNodes) {
      if (alreadyHasY) continue;
      final double y = (flipY ? -n.gen : n.gen) * TreeMetrics.rowHeight;
      n.y = y;
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
        ),
      );
    }

    final connectors = _buildConnectors(r, byId, rectById);

    final Size size = Size(
      maxX - minX + TreeMetrics.padding * 2,
      maxY - minY + TreeMetrics.padding * 2,
    );

    final int generations =
        gens ?? (r.allNodes.map((n) => n.gen).fold<int>(0, (a, b) => a > b ? a : b) + 1);

    return TreeLayout(
      nodes: positioned,
      connectors: connectors,
      size: size,
      generations: generations,
      focusRect: rectById[focusId] ?? Rect.zero,
    );
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
  _Node(this.id, this.gen, this.x, [this.y = 0]);
  final String id;
  final int gen;
  double x;
  double y;

  _Node copy({double? x, double? y}) => _Node(id, gen, x ?? this.x, y ?? this.y);
}

class _LayoutResult {
  _LayoutResult(this.byId);
  final Map<String, Person> byId;
  final List<_Node> allNodes = <_Node>[];
  final Map<int, List<_Node>> nodesByGen = <int, List<_Node>>{};
  int maxGen = 0;

  void add(_Node n) {
    allNodes.add(n);
    nodesByGen.putIfAbsent(n.gen, () => <_Node>[]).add(n);
    if (n.gen > maxGen) maxGen = n.gen;
  }
}

/// Top-down layout: focus at gen 0, children below. Pairs spouses.
class _Descendants {
  _Descendants(this.byId);
  final Map<String, Person> byId;
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
    final children = _childrenOf(person);

    final double unit = TreeMetrics.cardWidth + TreeMetrics.hGap;
    final double coupleSpan = spouse != null
        ? TreeMetrics.cardWidth * 2 + TreeMetrics.spouseGap
        : TreeMetrics.cardWidth;

    double centre;
    if (children.isEmpty) {
      final double left = _cursor;
      centre = left + coupleSpan / 2;
      _place(person, gen, left);
      if (spouse != null) {
        _visited.add(spouse.id);
        _place(
          spouse,
          gen,
          left + TreeMetrics.cardWidth + TreeMetrics.spouseGap,
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
      double left = centre - coupleSpan / 2;
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
        );
      }
      final double right = left + coupleSpan;
      if (right + TreeMetrics.hGap > _cursor) {
        _cursor = right + TreeMetrics.hGap;
      }
    }
    // Silence unused warning for `unit` on some paths.
    assert(unit > 0);
    return centre;
  }

  void _place(Person p, int gen, double x) => result.add(_Node(p.id, gen, x));
}

/// Bottom-up layout: focus at gen 0, parents above (binary-ish pedigree).
class _Ancestors {
  _Ancestors(this.byId);
  final Map<String, Person> byId;
  final _LayoutResult result = _LayoutResult(<String, Person>{});
  double _cursor = 0;
  final Set<String> _visited = <String>{};

  _LayoutResult run(Person focus) {
    result.byId.addAll(byId);
    _layout(focus, 0);
    return result;
  }

  double _layout(Person person, int gen) {
    if (_visited.contains(person.id)) {
      final existing = result.allNodes.firstWhere((n) => n.id == person.id);
      return existing.x + TreeMetrics.cardWidth / 2;
    }
    _visited.add(person.id);

    final parents = person.parentIds
        .where(byId.containsKey)
        .map((id) => byId[id]!)
        .toList();

    double centre;
    if (parents.isEmpty) {
      final double left = _cursor;
      centre = left + TreeMetrics.cardWidth / 2;
      result.add(_Node(person.id, gen, left));
      _cursor = left + TreeMetrics.cardWidth + TreeMetrics.hGap;
    } else {
      final int subtreeStart = result.allNodes.length;
      final parentCentres = <double>[];
      for (final p in parents) {
        parentCentres.add(_layout(p, gen + 1));
      }
      centre = (parentCentres.first + parentCentres.last) / 2;
      double left = centre - TreeMetrics.cardWidth / 2;
      if (left < _cursor) {
        final double delta = _cursor - left;
        for (int i = subtreeStart; i < result.allNodes.length; i++) {
          result.allNodes[i].x += delta;
        }
        centre += delta;
        left = centre - TreeMetrics.cardWidth / 2;
      }
      result.add(_Node(person.id, gen, left));
      final double right = left + TreeMetrics.cardWidth;
      if (right + TreeMetrics.hGap > _cursor) {
        _cursor = right + TreeMetrics.hGap;
      }
    }
    return centre;
  }
}
