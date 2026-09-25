import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../models/event.dart';
import '../../screens/auth/login_screen.dart';
import '../../state/auth_provider.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import 'create_event_sheet.dart';

/// «Добавить в мой той» (brief section 10) — the one entry point both
/// `ServiceDetailScreen` (ordinary service, no variant) and
/// `RestaurantDetailScreen` (a hall/menu/guests/estimatedTotal snapshot)
/// push a candidate through, mirroring `AddToEventMenu.jsx`'s own three
/// branches: logged out → login prompt; no events → offer to create one;
/// one or more events → pick one (a single event skips straight to a
/// confirm, matching the brief's own "если одно — bottom sheet
/// подтверждения").
Future<void> openAddToEventSheet(
  BuildContext context, {
  required int listingId,
  int? hallId,
  int? menuId,
  int? guests,
  int? estimatedTotal,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AddToEventSheet(
      listingId: listingId,
      hallId: hallId,
      menuId: menuId,
      guests: guests,
      estimatedTotal: estimatedTotal,
    ),
  );
}

class AddToEventSheet extends ConsumerWidget {
  const AddToEventSheet({
    super.key,
    required this.listingId,
    this.hallId,
    this.menuId,
    this.guests,
    this.estimatedTotal,
  });

  final int listingId;
  final int? hallId;
  final int? menuId;
  final int? guests;
  final int? estimatedTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final authState = ref.watch(authProvider);

    return _Sheet(
      child: switch (authState) {
        AuthInitial() || AuthLoading() => Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: context.mereytoiColors.goldPrimary,
            ),
          ),
        ),
        AuthUnauthenticated() => _LoginPrompt(locale: locale),
        AuthAuthenticated() => _EventPicker(
          listingId: listingId,
          hallId: hallId,
          menuId: menuId,
          guests: guests,
          estimatedTotal: estimatedTotal,
          locale: locale,
        ),
      },
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: context.mereytoiColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  const _LoginPrompt({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          t(
            locale,
            ru: 'Войдите, чтобы добавить в мой той',
            kz: 'Тойыма қосу үшін кіріңіз',
            en: 'Sign in to add to My Event',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
          },
          child: Text(t(locale, ru: 'Войти', kz: 'Кіру', en: 'Sign in')),
        ),
      ],
    );
  }
}

class _EventPicker extends ConsumerStatefulWidget {
  const _EventPicker({
    required this.listingId,
    this.hallId,
    this.menuId,
    this.guests,
    this.estimatedTotal,
    required this.locale,
  });

  final int listingId;
  final int? hallId;
  final int? menuId;
  final int? guests;
  final int? estimatedTotal;
  final AppLocale locale;

  @override
  ConsumerState<_EventPicker> createState() => _EventPickerState();
}

class _EventPickerState extends ConsumerState<_EventPicker> {
  int? _addingEventId;
  String? _error;

  Future<void> _add(int eventId) async {
    setState(() {
      _addingEventId = eventId;
      _error = null;
    });
    try {
      final (_, alreadyAdded) = await ref
          .read(eventActionsProvider)
          .addCandidate(
            eventId: eventId,
            listingId: widget.listingId,
            hallId: widget.hallId,
            menuId: widget.menuId,
            guests: widget.guests,
            estimatedTotal: widget.estimatedTotal,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            alreadyAdded
                ? t(
                    widget.locale,
                    ru: 'Уже в этом мероприятии',
                    kz: 'Бұл іс-шарада бар',
                    en: 'Already in this event',
                  )
                : t(
                    widget.locale,
                    ru: 'Добавлено в мой той',
                    kz: 'Тойыма қосылды',
                    en: 'Added to My Event',
                  ),
          ),
        ),
      );
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(widget.locale, err);
          _addingEventId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final locale = widget.locale;

    return eventsAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: context.mereytoiColors.goldPrimary,
          ),
        ),
      ),
      error: (err, _) => Text(
        apiErrorMessage(locale, err),
        style: TextStyle(color: context.mereytoiColors.error),
      ),
      data: (events) {
        if (events.isEmpty) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t(
                  locale,
                  ru: 'У вас пока нет мероприятий',
                  kz: 'Сізде әлі іс-шара жоқ',
                  en: 'You don\'t have any events yet',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openCreateEventSheet(context);
                },
                child: Text(
                  t(
                    locale,
                    ru: 'Создать мероприятие',
                    kz: 'Іс-шара құру',
                    en: 'Create event',
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t(
                locale,
                ru: 'Добавить в мой той',
                kz: 'Тойыма қосу',
                en: 'Add to My Event',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: context.mereytoiColors.error,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: events.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.xxs),
                itemBuilder: (context, i) => _EventRow(
                  event: events[i],
                  busy: _addingEventId == events[i].id,
                  onTap: _addingEventId == null
                      ? () => _add(events[i].id)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                openCreateEventSheet(context);
              },
              child: Text(
                t(
                  locale,
                  ru: '+ Новое мероприятие',
                  kz: '+ Жаңа іс-шара',
                  en: '+ New event',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.busy,
    required this.onTap,
  });

  final Event event;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.mereytoiColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Text(
                eventTypeEmoji(event.type),
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: context.mereytoiColors.goldPrimary,
                  ),
                )
              else
                Icon(
                  Icons.add_rounded,
                  color: context.mereytoiColors.goldPrimary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
