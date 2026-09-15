import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/event/event_status.dart';
import '../../models/event_candidate.dart';
import '../../state/auth_provider.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';
import '../app_error_view.dart';
import '../app_loader.dart';
import 'candidate_comments_sheet.dart';

/// Brief section 9 — the shortlist, the key tab. Only the actions the real
/// API actually allows: select/reject/back-to-shortlist (`UpdateStatus`),
/// remove (`RemoveCandidate` — owner, or whoever added it), and vote (any
/// member, viewers included).
class CandidatesTab extends ConsumerWidget {
  const CandidatesTab({super.key, required this.eventId, required this.myRole});

  final int eventId;
  final String myRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final candidatesAsync = ref.watch(eventCandidatesProvider(eventId));
    final authState = ref.watch(authProvider);
    final myUserId = authState is AuthAuthenticated ? authState.user.id : null;

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: () => ref.refresh(eventCandidatesProvider(eventId).future),
      child: candidatesAsync.when(
        loading: () => const AppLoader(),
        error: (err, _) => ListView(
          children: [
            SizedBox(
              height: 420,
              child: AppErrorView(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(eventCandidatesProvider(eventId)),
              ),
            ),
          ],
        ),
        data: (candidates) {
          if (candidates.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: 420,
                  child: Center(
                    child: Text(
                      t(
                        locale,
                        ru: 'Пока ничего не добавлено',
                        kz: 'Әлі ештеңе қосылмаған',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) => _CandidateCard(
              eventId: eventId,
              candidate: candidates[i],
              myRole: myRole,
              myUserId: myUserId,
              locale: locale,
            ),
          );
        },
      ),
    );
  }
}

class _CandidateCard extends ConsumerStatefulWidget {
  const _CandidateCard({
    required this.eventId,
    required this.candidate,
    required this.myRole,
    required this.myUserId,
    required this.locale,
  });

  final int eventId;
  final EventCandidate candidate;
  final String myRole;
  final int? myUserId;
  final AppLocale locale;

  @override
  ConsumerState<_CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends ConsumerState<_CandidateCard> {
  bool _busy = false;

  bool get _canRemove =>
      widget.myRole == eventRoleOwner ||
      widget.candidate.addedById == widget.myUserId;
  bool get _canDecide =>
      eventRoleRank(widget.myRole) >= eventRoleRank(eventRoleEditor);

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventActionsProvider)
          .updateCandidateStatus(
            eventId: widget.eventId,
            candidateId: widget.candidate.id,
            status: status,
          );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(widget.locale, err))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventActionsProvider)
          .removeCandidate(
            eventId: widget.eventId,
            candidateId: widget.candidate.id,
          );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(widget.locale, err))),
        );
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _vote(String value) async {
    try {
      await ref
          .read(eventActionsProvider)
          .vote(
            eventId: widget.eventId,
            candidateId: widget.candidate.id,
            value: value,
          );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(widget.locale, err))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final candidate = widget.candidate;
    final listing = candidate.listing;

    final title =
        listing?.name(locale) ?? t(locale, ru: 'Услуга', kz: 'Қызмет');
    final hallName = candidate.hall?.name(locale) ?? candidate.hallName;
    final menuName = candidate.menu?.name(locale) ?? candidate.menuName;
    final price =
        candidate.estimatedTotal ??
        (candidate.menuPricePerGuest != null && candidate.guests != null
            ? candidate.menuPricePerGuest! * candidate.guests!
            : listing?.price);

    return Opacity(
      opacity: _busy ? 0.6 : 1,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                _StatusBadge(status: candidate.status, locale: locale),
              ],
            ),
            if (hallName != null ||
                menuName != null ||
                candidate.guests != null) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: 2,
                children: [
                  if (hallName != null && hallName.isNotEmpty)
                    _MiniFact(hallName),
                  if (menuName != null && menuName.isNotEmpty)
                    _MiniFact(menuName),
                  if (candidate.guests != null)
                    _MiniFact(
                      '${candidate.guests} ${t(locale, ru: "гостей", kz: "қонақ")}',
                    ),
                ],
              ),
            ],
            if (price != null) ...[
              const SizedBox(height: 4),
              Text(
                formatPrice(price),
                style: TextStyle(
                  color: context.mereytoiColors.goldSoft,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                _VoteButton(
                  icon: Icons.thumb_up_alt_outlined,
                  count: candidate.votes[voteUp] ?? 0,
                  active: candidate.myVote == voteUp,
                  onTap: () => _vote(voteUp),
                ),
                const SizedBox(width: AppSpacing.xs),
                _VoteButton(
                  icon: Icons.help_outline_rounded,
                  count: candidate.votes[voteMaybe] ?? 0,
                  active: candidate.myVote == voteMaybe,
                  onTap: () => _vote(voteMaybe),
                ),
                const SizedBox(width: AppSpacing.xs),
                _VoteButton(
                  icon: Icons.thumb_down_alt_outlined,
                  count: candidate.votes[voteDown] ?? 0,
                  active: candidate.myVote == voteDown,
                  onTap: () => _vote(voteDown),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => CandidateCommentsSheet(
                      eventId: widget.eventId,
                      candidateId: candidate.id,
                    ),
                  ),
                  icon: Badge(
                    label: Text('${candidate.commentCount}'),
                    isLabelVisible: candidate.commentCount > 0,
                    backgroundColor: context.mereytoiColors.surfaceSoft,
                    textStyle: TextStyle(
                      fontSize: 10,
                      color: context.mereytoiColors.textPrimary,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: context.mereytoiColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (_canDecide || _canRemove) ...[
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xxs,
                children: [
                  if (_canDecide && candidate.status != candidateSelected)
                    _ActionChip(
                      label: t(locale, ru: 'Выбрать', kz: 'Таңдау'),
                      onTap: _busy ? null : () => _setStatus(candidateSelected),
                    ),
                  if (_canDecide && candidate.status != candidateRejected)
                    _ActionChip(
                      label: t(locale, ru: 'Отклонить', kz: 'Қабылдамау'),
                      onTap: _busy ? null : () => _setStatus(candidateRejected),
                    ),
                  if (_canDecide && candidate.status != candidateShortlisted)
                    _ActionChip(
                      label: t(locale, ru: 'В шортлист', kz: 'Шортлистке'),
                      onTap: _busy
                          ? null
                          : () => _setStatus(candidateShortlisted),
                    ),
                  if (_canRemove)
                    _ActionChip(
                      label: t(locale, ru: 'Удалить', kz: 'Жою'),
                      destructive: true,
                      onTap: _busy ? null : _remove,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.locale});

  final String status;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      candidateSelected => context.mereytoiColors.success,
      candidateRejected => context.mereytoiColors.error,
      _ => context.mereytoiColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        candidateStatusLabel(locale, status),
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.mereytoiColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.icon,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? context.mereytoiColors.goldPrimary.withValues(alpha: 0.16)
          : context.mereytoiColors.surfaceSoft,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: active
                    ? context.mereytoiColors.goldPrimary
                    : context.mereytoiColors.textSecondary,
              ),
              if (count > 0) ...[
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    color: active
                        ? context.mereytoiColors.goldPrimary
                        : context.mereytoiColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: destructive
                  ? context.mereytoiColors.error.withValues(alpha: 0.4)
                  : context.mereytoiColors.divider,
            ),
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: destructive
                  ? context.mereytoiColors.error
                  : context.mereytoiColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
