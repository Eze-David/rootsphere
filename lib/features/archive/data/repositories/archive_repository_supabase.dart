import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../../records/domain/entities/record.dart';
import '../../domain/entities/archive_record.dart';
import '../../domain/repositories/archive_repository.dart';

/// Supabase-backed [ArchiveRepository].
///
/// Records live in an `archive_records` table gated entirely by
/// `public.is_platform_admin()` RLS (see migration
/// 20260916000000_archive_records.sql) — every method here only ever
/// succeeds for an admin; anyone else gets an empty stream / RLS error.
class ArchiveRepositorySupabase implements ArchiveRepository {
  ArchiveRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('archive_records');

  String get _uid => _client.auth.currentUser?.id ?? '';

  @override
  Stream<List<ArchiveRecord>> watchAll() {
    return _table.stream(primaryKey: <String>['id']).order('created_at').map((
      rows,
    ) {
      final records = rows.map(_fromRow).toList();
      records.sort((a, b) {
        final DateTime ad = a.createdAt ?? DateTime(0);
        final DateTime bd = b.createdAt ?? DateTime(0);
        return bd.compareTo(ad);
      });
      return records;
    });
  }

  @override
  Future<void> upsertRecord(ArchiveRecord record) async {
    try {
      await _table.upsert(_toRow(record));
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> submitForReview(String id) async {
    try {
      await _table.update(<String, dynamic>{'review_status': 'pending_review'}).eq(
        'id',
        id,
      );
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> review(String id, {required bool approved, String? note}) async {
    try {
      await _table
          .update(<String, dynamic>{
            'review_status': approved ? 'published' : 'rejected',
            // Access level is an explicit admin choice on the form,
            // independent of the review decision — not touched here.
            'reviewer_note': note,
            'reviewed_by': _uid,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> deleteRecord(String id) async {
    try {
      await _table.delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  // ── Mapping ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _toRow(ArchiveRecord r) => <String, dynamic>{
    'id': r.id,
    'record_ref': r.recordRef,
    'title': r.title,
    'type': r.type.name,
    'collection': r.collection,
    'country': r.country,
    'state_region': r.stateRegion,
    'locality': r.locality,
    'date_range_start': r.dateRangeStart,
    'date_range_end': r.dateRangeEnd,
    'repository_source': r.repositorySource,
    'contributor': r.contributor,
    'keywords': r.keywords,
    'description': r.description,
    'files': r.files.map((f) => f.toJson()).toList(),
    'search_text': r.searchText,
    'access_status': r.accessStatus.name,
    'review_status': r.reviewStatus.name,
    'reviewer_note': r.reviewerNote,
    'created_by': r.createdBy ?? _uid,
  };

  ArchiveRecord _fromRow(Map<String, dynamic> row) {
    DateTime? parse(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return ArchiveRecord(
      id: row['id'] as String,
      recordRef: row['record_ref'] as String?,
      title: row['title'] as String? ?? '',
      type: RecordType.values.firstWhere(
        (t) => t.name == row['type'],
        orElse: () => RecordType.other,
      ),
      collection: row['collection'] as String? ?? '',
      country: row['country'] as String? ?? '',
      stateRegion: row['state_region'] as String? ?? '',
      locality: row['locality'] as String? ?? '',
      dateRangeStart: row['date_range_start'] as int?,
      dateRangeEnd: row['date_range_end'] as int?,
      repositorySource: row['repository_source'] as String? ?? '',
      contributor: row['contributor'] as String? ?? '',
      keywords: (row['keywords'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(),
      description: row['description'] as String?,
      files: (row['files'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => ArchiveFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      searchText: row['search_text'] as String?,
      accessStatus: ArchiveAccessStatus.values.firstWhere(
        (a) => a.name == row['access_status'],
        orElse: () => ArchiveAccessStatus.permission,
      ),
      reviewStatus: ArchiveReviewStatus.values.firstWhere(
        (s) => s.name == _camelToSnakeMatch(row['review_status']),
        orElse: () => ArchiveReviewStatus.draft,
      ),
      reviewerNote: row['reviewer_note'] as String?,
      createdBy: row['created_by'] as String?,
      reviewedBy: row['reviewed_by'] as String?,
      createdAt: parse(row['created_at']),
      updatedAt: parse(row['updated_at']),
      reviewedAt: parse(row['reviewed_at']),
    );
  }

  /// `review_status` is stored snake_case ('pending_review') in Postgres but
  /// the Dart enum names are camelCase ('pendingReview') — normalize before
  /// matching against `.name`.
  String _camelToSnakeMatch(dynamic dbValue) {
    final String v = (dbValue as String? ?? 'draft');
    final List<String> parts = v.split('_');
    if (parts.length == 1) return parts.first;
    return parts.first +
        parts.skip(1).map((p) => p.isEmpty ? '' : p[0].toUpperCase() + p.substring(1)).join();
  }
}
