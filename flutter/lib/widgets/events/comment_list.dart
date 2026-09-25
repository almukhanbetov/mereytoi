import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../models/event_comment.dart';
import '../../state/auth_provider.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_error_view.dart';
import '../app_loader.dart';

/// Shared between the "Обсуждение" tab (`candidateId == null`) and a
/// per-candidate comment thread (`candidateId` set) — same list + add-form
/// shape either way, matching the backend's own one-table-either-way
/// design (`EventComment`'s own doc comment). Deliberately a different
/// feature from Manager Chat (brief section 13) — this is workspace-team
/// discussion, never routed anywhere near that channel.
class EventCommentList extends ConsumerStatefulWidget {
  const EventCommentList({super.key, required this.eventId, this.candidateId});

  final int eventId;
  final int? candidateId;

  @override
  ConsumerState<EventCommentList> createState() => _EventCommentListState();
}

class _EventCommentListState extends ConsumerState<EventCommentList> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  EventCommentsKey get _key => (widget.eventId, widget.candidateId);

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(eventActionsProvider)
          .addComment(
            eventId: widget.eventId,
            body: body,
            candidateId: widget.candidateId,
          );
      _controller.clear();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(ref.read(localeProvider), err)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(EventComment comment) async {
    try {
      await ref
          .read(eventActionsProvider)
          .deleteComment(
            eventId: widget.eventId,
            commentId: comment.id,
            candidateId: widget.candidateId,
          );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(ref.read(localeProvider), err)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final commentsAsync = ref.watch(eventCommentsProvider(_key));
    final authState = ref.watch(authProvider);
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final myRole =
        ref.watch(eventDetailProvider(widget.eventId)).valueOrNull?.myRole ??
        eventRoleViewer;

    return Column(
      children: [
        Expanded(
          child: commentsAsync.when(
            loading: () => const AppLoader(),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(eventCommentsProvider(_key)),
            ),
            data: (comments) {
              if (comments.isEmpty) {
                return Center(
                  child: Text(
                    t(
                      locale,
                      ru: 'Пока нет сообщений',
                      kz: 'Әлі хабарлама жоқ',
                      en: 'No messages yet',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: comments.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final comment = comments[i];
                  final canDelete =
                      comment.userId == myUserId || myRole == eventRoleOwner;
                  return _CommentTile(
                    comment: comment,
                    canDelete: canDelete,
                    onDelete: () => _delete(comment),
                  );
                },
              );
            },
          ),
        ),
        // Posting needs editor+ (`EventCommentHandler.AddComment` is
        // mounted only under the editor route group) — a viewer can read
        // every thread but the input row simply isn't shown for them,
        // rather than letting them submit into a guaranteed 403.
        if (eventRoleRank(myRole) >= eventRoleRank(eventRoleEditor))
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: t(
                          locale,
                          ru: 'Написать сообщение…',
                          kz: 'Хабарлама жазу…',
                          en: 'Write a message…',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.canDelete,
    required this.onDelete,
  });

  final EventComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: context.mereytoiColors.surfaceSoft,
          child: Text(
            (comment.user?.name.isNotEmpty ?? false)
                ? comment.user!.name.substring(0, 1).toUpperCase()
                : '?',
            style: TextStyle(
              fontSize: 12,
              color: context.mereytoiColors.goldPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      comment.user?.name ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (canDelete)
                    InkWell(
                      onTap: onDelete,
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: context.mereytoiColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              Text(comment.body, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
