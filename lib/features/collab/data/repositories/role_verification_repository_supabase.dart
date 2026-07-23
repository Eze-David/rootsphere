import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/opportunity.dart';
import '../../domain/entities/role_verification.dart';
import '../../domain/repositories/role_verification_repository.dart';

class RoleVerificationRepositorySupabase implements RoleVerificationRepository {
  RoleVerificationRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _table => _client.from('role_verifications');

  String get _uid => _client.auth.currentUser?.id ?? '';

  String get _userName {
    final user = _client.auth.currentUser;
    final meta = user?.userMetadata;
    final name = (meta?['full_name'] ?? meta?['name']) as String?;
    return name?.trim().isNotEmpty == true
        ? name!.trim()
        : user?.email ?? 'You';
  }

  @override
  Stream<List<RoleVerification>> watchMine() {
    if (_uid.isEmpty) return Stream<List<RoleVerification>>.value(const []);
    return _table
        .stream(primaryKey: <String>['id'])
        .eq('user_id', _uid)
        .map((rows) => rows.map(RoleVerification.fromJson).toList());
  }

  @override
  Future<void> apply({
    required CollaborationRole role,
    required String email,
    required String phone,
    required String governmentIdUrl,
    String? note,
    List<String> documentUrls = const <String>[],
  }) async {
    if (_uid.isEmpty) throw const AuthFailure('You must be signed in.');
    try {
      await _table.upsert(<String, dynamic>{
        'user_id': _uid,
        'applicant_name': _userName,
        'applicant_email': email,
        'applicant_phone': phone,
        'role': role.name,
        'status': 'pending',
        'note': note,
        'document_urls': documentUrls,
        'government_id_url': governmentIdUrl,
        'reviewed_at': null,
        'reviewed_by': null,
      }, onConflict: 'user_id,role');
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<bool> isAdmin() async {
    if (_uid.isEmpty) return false;
    try {
      final dynamic result = await _client.rpc('is_platform_admin');
      return result == true;
    } on PostgrestException {
      return false;
    }
  }

  @override
  Stream<List<RoleVerification>> watchPending() {
    return _table
        .stream(primaryKey: <String>['id'])
        .eq('status', 'pending')
        .order('created_at')
        .map((rows) => rows.map(RoleVerification.fromJson).toList());
  }

  @override
  Future<void> review(String id, {required bool approve}) async {
    try {
      await _table
          .update(<String, dynamic>{
            'status': approve ? 'approved' : 'rejected',
            'reviewed_at': DateTime.now().toIso8601String(),
            'reviewed_by': _uid,
          })
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}
