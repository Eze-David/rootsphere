import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/repositories/support_message_repository_local.dart';
import '../../data/repositories/support_message_repository_supabase.dart';
import '../../domain/entities/support_message.dart';
import '../../domain/entities/support_message_reply.dart';
import '../../domain/repositories/support_message_repository.dart';

final supportMessageRepositoryProvider = Provider<SupportMessageRepository>((
  ref,
) {
  if (SupabaseConfig.isReady) {
    return SupportMessageRepositorySupabase(SupabaseConfig.client);
  }
  return SupportMessageRepositoryLocal();
});

/// Every submitted message, newest first — admin inbox only (RLS blocks this
/// from returning anything for a non-admin anyway).
final supportMessagesProvider =
    StreamProvider.autoDispose<List<SupportMessage>>((ref) {
      ref.watch(authStateProvider);
      return ref.watch(supportMessageRepositoryProvider).watchAll();
    });

/// A single message's reply thread, oldest first.
final supportMessageRepliesProvider = StreamProvider.autoDispose
    .family<List<SupportMessageReply>, String>((ref, messageId) {
      return ref
          .watch(supportMessageRepositoryProvider)
          .watchReplies(messageId);
    });
