/// A single audit-log entry recording why a person record was edited.
///
/// Captured every time an existing [Person] is saved from the editor. Stored
/// per tree so collaborators can see who changed what and why.
class EditHistoryEntry {
  const EditHistoryEntry({
    required this.id,
    required this.treeId,
    required this.personId,
    required this.reason,
    this.editorId,
    this.editorName,
    this.changedFields = const <String>[],
    required this.createdAt,
  });

  final String id;
  final String treeId;
  final String personId;

  /// The user-provided reason for the edit (required at save time).
  final String reason;

  /// The editor's auth id / display name, when known.
  final String? editorId;
  final String? editorName;

  /// Names of the fields that changed in this edit (for a quick summary).
  final List<String> changedFields;

  final DateTime createdAt;

  EditHistoryEntry copyWith({
    String? editorId,
    String? editorName,
    List<String>? changedFields,
  }) {
    return EditHistoryEntry(
      id: id,
      treeId: treeId,
      personId: personId,
      reason: reason,
      editorId: editorId ?? this.editorId,
      editorName: editorName ?? this.editorName,
      changedFields: changedFields ?? this.changedFields,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'treeId': treeId,
        'personId': personId,
        'reason': reason,
        'editorId': editorId,
        'editorName': editorName,
        'changedFields': changedFields,
        'createdAt': createdAt.toIso8601String(),
      };

  factory EditHistoryEntry.fromJson(Map<String, dynamic> json) {
    return EditHistoryEntry(
      id: json['id'] as String,
      treeId: json['treeId'] as String,
      personId: json['personId'] as String,
      reason: json['reason'] as String? ?? '',
      editorId: json['editorId'] as String?,
      editorName: json['editorName'] as String?,
      changedFields:
          (json['changedFields'] as List<dynamic>? ?? const <dynamic>[])
              .map((e) => e.toString())
              .toList(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}
