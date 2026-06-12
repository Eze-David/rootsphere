/// Lightweight representation of a family tree the user is linked to.
///
/// Full tree modelling (members, relationships, records) lives in Phase 2.
/// This entity is used in the Profile screen for tree-linking UI.
class FamilyTree {
  const FamilyTree({
    required this.id,
    required this.name,
    required this.role,
    this.memberCount = 0,
  });

  final String id;
  final String name;
  final TreeRole role;
  final int memberCount;

  @override
  bool operator ==(Object other) =>
      other is FamilyTree &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.memberCount == memberCount;

  @override
  int get hashCode => Object.hash(id, name, role, memberCount);
}

enum TreeRole { owner, editor, viewer }
