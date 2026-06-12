import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

/// Drives auth form submissions and exposes a loading/error state to the UI.
///
/// Uses Riverpod 3's [AsyncNotifier]; `state` is an `AsyncValue<void>` where
/// `loading` = request in flight and `error` = a [Failure] to surface.
class AuthController extends AsyncNotifier<void> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<void> build() async {}

  Future<bool> signIn(String email, String password) {
    return _run(() => _repo.signInWithEmail(email: email, password: password));
  }

  Future<bool> signUp(String email, String password) {
    return _run(() => _repo.signUpWithEmail(email: email, password: password));
  }

  Future<bool> signInWithGoogle() => _run(_repo.signInWithGoogle);

  Future<bool> signInWithApple() => _run(_repo.signInWithApple);

  Future<bool> sendPasswordReset(String email) {
    return _run(() => _repo.sendPasswordReset(email));
  }

  Future<bool> signOut() => _run(_repo.signOut);

  Future<bool> updatePassword(String newPassword) {
    return _run(() => _repo.updatePassword(newPassword));
  }

  Future<bool> deleteAccount() => _run(_repo.deleteAccount);

  Future<bool> resendEmailConfirmation(String email) {
    return _run(() => _repo.resendEmailConfirmation(email));
  }

  /// Runs [action], updating [state]. Returns `true` on success.
  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncValue<void>.loading();
    try {
      await action();
      state = const AsyncValue<void>.data(null);
      return true;
    } on Failure catch (e, st) {
      state = AsyncValue<void>.error(e, st);
      return false;
    } catch (e, st) {
      state = AsyncValue<void>.error(const UnknownFailure(), st);
      return false;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
