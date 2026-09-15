import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/event/event_status.dart';
import '../../models/event.dart';
import '../../state/auth_provider.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/events/create_event_sheet.dart';
import '../auth/login_screen.dart';
import 'event_workspace_screen.dart';

/// «Мой той» — the mobile counterpart of the site's /profile/events list
/// (brief section 5): every event the caller belongs to (any role), via
/// the real `GET /api/events`. Every Event Workspace endpoint requires
/// auth, so this never calls it while logged out (brief section 20) — it
/// shows a login prompt instead of a guaranteed 401.
class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Мой той', kz: 'Менің тойым')),
      ),
      body: switch (authState) {
        AuthInitial() || AuthLoading() => const AppLoader(),
        AuthUnauthenticated() => _LoginPrompt(locale: locale),
        AuthAuthenticated() => const _EventsList(),
      },
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(icon: Icons.celebration_outlined),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Войдите, чтобы планировать той',
                kz: 'Тойды жоспарлау үшін кіріңіз',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: Text(t(locale, ru: 'Войти', kz: 'Кіру')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsList extends ConsumerWidget {
  const _EventsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final eventsAsync = ref.watch(eventsProvider);

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: () => ref.refresh(eventsProvider.future),
      child: eventsAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: List.generate(
            3,
            (_) => const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppSkeleton(height: 108, borderRadius: AppRadius.lg),
            ),
          ),
        ),
        error: (err, _) => ListView(
          children: [
            SizedBox(
              height: 420,
              child: AppErrorView(
                message: apiErrorMessage(locale, err),
                locale: locale,
                onRetry: () => ref.invalidate(eventsProvider),
              ),
            ),
          ],
        ),
        data: (events) {
          if (events.isEmpty) {
            return ListView(
              children: [
                SizedBox(height: 420, child: _EmptyEvents(locale: locale)),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              100,
            ),
            itemCount: events.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) =>
                _EventCard(event: events[i], locale: locale),
          );
        },
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(icon: Icons.celebration_outlined),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'У вас пока нет мероприятий',
                kz: 'Сізде әлі іс-шара жоқ',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => openCreateEventSheet(context),
              child: Text(
                t(locale, ru: 'Создать мероприятие', kz: 'Іс-шара құру'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.locale});

  final Event event;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventWorkspaceScreen(eventId: event.id),
        ),
      ),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eventTypeEmoji(event.type),
              style: const TextStyle(fontSize: 26),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: AppSpacing.xxs,
                    runSpacing: 4,
                    children: [
                      if (event.eventDate != null)
                        _MetaBit(
                          icon: Icons.event_outlined,
                          text: formatMenuDate(event.eventDate!),
                        ),
                      if (event.city.isNotEmpty)
                        _MetaBit(icon: Icons.place_outlined, text: event.city),
                      _MetaBit(
                        icon: Icons.flag_outlined,
                        text: event.status == eventStatusSubmitted
                            ? t(locale, ru: 'Отправлено', kz: 'Жіберілді')
                            : t(locale, ru: 'Планирование', kz: 'Жоспарлау'),
                      ),
                    ],
                  ),
                  if (event.budgetTotal > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${t(locale, ru: "Бюджет", kz: "Бюджет")}: ${formatPrice(event.budgetTotal)}',
                      style: TextStyle(
                        color: context.mereytoiColors.goldSoft,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.mereytoiColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaBit extends StatelessWidget {
  const _MetaBit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: context.mereytoiColors.textMuted),
        const SizedBox(width: 3),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
