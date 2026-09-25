import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/events/budget_tab.dart';
import '../../widgets/events/candidates_tab.dart';
import '../../widgets/events/discussion_tab.dart';
import '../../widgets/events/members_tab.dart';
import '../../widgets/events/overview_tab.dart';
import '../../widgets/events/tasks_tab.dart';

/// The event workspace itself — brief section 7: a summary header + tabs,
/// never one giant scroll. Six tabs, matching the brief's own recommended
/// set 1:1 (Обзор/Услуги/Бюджет/Обсуждение/Задачи/Участники).
class EventWorkspaceScreen extends ConsumerWidget {
  const EventWorkspaceScreen({
    super.key,
    required this.eventId,
    this.initialTabIndex = 0,
  });

  final int eventId;

  /// Deep-link support (brief section 10) — a notification opened for
  /// e.g. a candidate lands straight on Услуги instead of always Обзор.
  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final eventAsync = ref.watch(eventDetailProvider(eventId));

    return DefaultTabController(
      length: 6,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: eventAsync.maybeWhen(
            data: (event) =>
                Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            orElse: () => Text(
              t(locale, ru: 'Мой той', kz: 'Менің тойым', en: 'My Event'),
            ),
          ),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: context.mereytoiColors.goldPrimary,
            labelColor: context.mereytoiColors.goldPrimary,
            unselectedLabelColor: context.mereytoiColors.textSecondary,
            tabs: [
              Tab(
                text: t(locale, ru: 'Обзор', kz: 'Шолу', en: 'Overview'),
              ),
              Tab(
                text: t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services'),
              ),
              Tab(
                text: t(locale, ru: 'Бюджет', kz: 'Бюджет', en: 'Budget'),
              ),
              Tab(
                text: t(
                  locale,
                  ru: 'Обсуждение',
                  kz: 'Талқылау',
                  en: 'Discussion',
                ),
              ),
              Tab(
                text: t(locale, ru: 'Задачи', kz: 'Тапсырмалар', en: 'Tasks'),
              ),
              Tab(
                text: t(
                  locale,
                  ru: 'Участники',
                  kz: 'Қатысушылар',
                  en: 'Members',
                ),
              ),
            ],
          ),
        ),
        body: eventAsync.when(
          loading: () => const AppLoader(),
          error: (err, _) => Center(
            child: AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(eventDetailProvider(eventId)),
            ),
          ),
          data: (event) {
            final myRole = event.myRole ?? eventRoleViewer;
            return TabBarView(
              children: [
                OverviewTab(eventId: eventId, event: event, myRole: myRole),
                CandidatesTab(eventId: eventId, myRole: myRole),
                BudgetTab(eventId: eventId, event: event),
                DiscussionTab(eventId: eventId, myRole: myRole),
                TasksTab(eventId: eventId, myRole: myRole),
                MembersTab(eventId: eventId, myRole: myRole),
              ],
            );
          },
        ),
      ),
    );
  }
}
