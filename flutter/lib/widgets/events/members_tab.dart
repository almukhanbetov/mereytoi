import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../models/event_member.dart';
import '../../state/auth_provider.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';
import '../app_error_view.dart';
import '../app_loader.dart';

/// Brief section 15 — members + the real invitation flow (a shareable
/// token link, `POST /api/events/:id/invitations` — never an invented
/// email/SMS send; the optional `email` field only additionally emails
/// the *same* link, see `EventMemberHandler.CreateInvitation`'s own doc
/// comment). Invitation management (creating/listing/revoking links,
/// changing a role, removing a member) is owner-only on the backend.
class MembersTab extends ConsumerWidget {
  const MembersTab({super.key, required this.eventId, required this.myRole});

  final int eventId;
  final String myRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final membersAsync = ref.watch(eventMembersProvider(eventId));
    final isOwner = myRole == eventRoleOwner;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: context.mereytoiColors.goldPrimary,
        backgroundColor: context.mereytoiColors.surfaceElevated,
        onRefresh: () => ref.refresh(eventMembersProvider(eventId).future),
        child: membersAsync.when(
          loading: () => const AppLoader(),
          error: (err, _) => ListView(
            children: [
              SizedBox(
                height: 420,
                child: AppErrorView(
                  message: apiErrorMessage(locale, err),
                  locale: locale,
                  onRetry: () => ref.invalidate(eventMembersProvider(eventId)),
                ),
              ),
            ],
          ),
          data: (members) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              90,
            ),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) => _MemberTile(
              eventId: eventId,
              member: members[i],
              isOwner: isOwner,
              locale: locale,
            ),
          ),
        ),
      ),
      floatingActionButton: isOwner
          ? FloatingActionButton(
              backgroundColor: context.mereytoiColors.goldPrimary,
              foregroundColor: context.mereytoiColors.onGold,
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _InviteSheet(eventId: eventId),
              ),
              child: const Icon(Icons.person_add_alt_1_rounded),
            )
          : null,
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.eventId,
    required this.member,
    required this.isOwner,
    required this.locale,
  });

  final int eventId;
  final EventMember member;
  final bool isOwner;
  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isMe =
        authState is AuthAuthenticated && authState.user.id == member.userId;
    final canManage = isOwner && member.role != eventRoleOwner;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: context.mereytoiColors.surfaceSoft,
            child: Text(
              (member.user?.name.isNotEmpty ?? false)
                  ? member.user!.name.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                color: context.mereytoiColors.goldPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${member.user?.name ?? '—'}${isMe ? ' (${t(locale, ru: "вы", kz: "сіз")})' : ''}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  eventRoleLabel(locale, member.role),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                color: context.mereytoiColors.textMuted,
                size: 20,
              ),
              onSelected: (value) async {
                try {
                  if (value == 'remove') {
                    await ref
                        .read(eventActionsProvider)
                        .removeMember(eventId: eventId, userId: member.userId);
                  } else {
                    await ref
                        .read(eventActionsProvider)
                        .changeMemberRole(
                          eventId: eventId,
                          userId: member.userId,
                          role: value,
                        );
                  }
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(apiErrorMessage(locale, err))),
                    );
                  }
                }
              },
              itemBuilder: (context) => [
                if (member.role != eventRoleEditor)
                  PopupMenuItem(
                    value: eventRoleEditor,
                    child: Text(
                      t(locale, ru: 'Сделать участником', kz: 'Қатысушы ету'),
                    ),
                  ),
                if (member.role != eventRoleViewer)
                  PopupMenuItem(
                    value: eventRoleViewer,
                    child: Text(
                      t(
                        locale,
                        ru: 'Сделать наблюдателем',
                        kz: 'Бақылаушы ету',
                      ),
                    ),
                  ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    t(
                      locale,
                      ru: 'Удалить из мероприятия',
                      kz: 'Іс-шарадан жою',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.eventId});

  final int eventId;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  String _role = eventRoleEditor;
  bool _submitting = false;
  String? _error;
  String? _link;

  Future<void> _create() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final invitation = await ref
          .read(eventActionsProvider)
          .createInvitation(eventId: widget.eventId, role: _role);
      // /invite/[token] is the site's own acceptance page
      // (frontend/src/app/invite/[token]/page.js), served from the same
      // origin as the API in production (see ApiConfig's own doc comment)
      // — the same link works whether it's opened on web or shared into a
      // chat and opened later.
      setState(() => _link = '${ApiConfig.baseUrl}/invite/${invitation.token}');
    } catch (err) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(ref.read(localeProvider), err));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(locale, ru: 'Пригласить участника', kz: 'Қатысушы шақыру'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.xxs,
                  children: [
                    ChoiceChip(
                      label: Text(eventRoleLabel(locale, eventRoleEditor)),
                      selected: _role == eventRoleEditor,
                      onSelected: (_) =>
                          setState(() => _role = eventRoleEditor),
                    ),
                    ChoiceChip(
                      label: Text(eventRoleLabel(locale, eventRoleViewer)),
                      selected: _role == eventRoleViewer,
                      onSelected: (_) =>
                          setState(() => _role = eventRoleViewer),
                    ),
                  ],
                ),
                if (_link != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: context.mereytoiColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _link!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _link!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  t(
                                    locale,
                                    ru: 'Ссылка скопирована',
                                    kz: 'Сілтеме көшірілді',
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: context.mereytoiColors.error,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _create,
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : Text(
                            t(locale, ru: 'Создать ссылку', kz: 'Сілтеме құру'),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
