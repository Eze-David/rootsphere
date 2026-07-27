import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../collab/presentation/providers/role_verification_providers.dart';
import '../../domain/entities/support_message.dart';
import '../../domain/entities/support_message_reply.dart';
import '../providers/support_message_providers.dart';

/// A single support message's thread — the original message plus replies
/// from either side, and a composer both the admin and the original sender
/// can use (RLS decides which; see
/// supabase/migrations/20260724030000_support_message_replies.sql).
class SupportMessageThreadScreen extends ConsumerStatefulWidget {
  const SupportMessageThreadScreen({super.key, required this.message});

  final SupportMessage message;

  @override
  ConsumerState<SupportMessageThreadScreen> createState() =>
      _SupportMessageThreadScreenState();
}

class _SupportMessageThreadScreenState
    extends ConsumerState<SupportMessageThreadScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(supportMessageRepositoryProvider)
          .reply(widget.message.id, body);
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not send reply.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = ref.watch(isPlatformAdminProvider).value ?? false;
    final bool resolved =
        widget.message.status == SupportMessageStatus.resolved;
    final AsyncValue<List<SupportMessageReply>> repliesAsync = ref.watch(
      supportMessageRepliesProvider(widget.message.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.message.email),
        actions: <Widget>[
          if (isAdmin && !resolved)
            TextButton(
              onPressed: () => ref
                  .read(supportMessageRepositoryProvider)
                  .markResolved(widget.message.id),
              child: const Text('Mark resolved'),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: repliesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (replies) {
                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: <Widget>[
                    _Bubble(body: widget.message.message, fromAdmin: false),
                    for (final r in replies)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: _Bubble(
                          body: r.body,
                          fromAdmin: r.isAdminReply,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a reply…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.body, required this.fromAdmin});

  final String body;
  final bool fromAdmin;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Align(
      alignment: fromAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: fromAdmin ? AppColors.primary : AppColors.cream,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Text(
          body,
          style: text.bodyMedium?.copyWith(
            color: fromAdmin ? AppColors.onPrimary : null,
          ),
        ),
      ),
    );
  }
}
