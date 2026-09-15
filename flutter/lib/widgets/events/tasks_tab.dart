import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/event/event_status.dart';
import '../../models/event_task.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';
import '../app_error_view.dart';
import '../app_loader.dart';

/// Brief section 14 — a flat checklist, not a Jira board. Any member can
/// flip a task done/undone; only editor+ can create/delete or edit its
/// title/assignee/due date (see `EventTaskHandler.Update`'s own
/// `onlyStatusChange` split, mirrored here in which actions are shown).
class TasksTab extends ConsumerWidget {
  const TasksTab({super.key, required this.eventId, required this.myRole});

  final int eventId;
  final String myRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final tasksAsync = ref.watch(eventTasksProvider(eventId));
    final canCreate = eventRoleRank(myRole) >= eventRoleRank(eventRoleEditor);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        color: context.mereytoiColors.goldPrimary,
        backgroundColor: context.mereytoiColors.surfaceElevated,
        onRefresh: () => ref.refresh(eventTasksProvider(eventId).future),
        child: tasksAsync.when(
          loading: () => const AppLoader(),
          error: (err, _) => ListView(
            children: [
              SizedBox(
                height: 420,
                child: AppErrorView(
                  message: apiErrorMessage(locale, err),
                  locale: locale,
                  onRetry: () => ref.invalidate(eventTasksProvider(eventId)),
                ),
              ),
            ],
          ),
          data: (tasks) {
            if (tasks.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: 420,
                    child: Center(
                      child: Text(
                        t(locale, ru: 'Пока нет задач', kz: 'Әлі тапсырма жоқ'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                90,
              ),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
              itemBuilder: (context, i) => _TaskTile(
                eventId: eventId,
                task: tasks[i],
                canManage: canCreate,
                locale: locale,
              ),
            );
          },
        ),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton(
              backgroundColor: context.mereytoiColors.goldPrimary,
              foregroundColor: context.mereytoiColors.onGold,
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _CreateTaskSheet(eventId: eventId),
              ),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

class _TaskTile extends ConsumerStatefulWidget {
  const _TaskTile({
    required this.eventId,
    required this.task,
    required this.canManage,
    required this.locale,
  });

  final int eventId;
  final EventTask task;
  final bool canManage;
  final AppLocale locale;

  @override
  ConsumerState<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<_TaskTile> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventActionsProvider)
          .updateTaskStatus(
            eventId: widget.eventId,
            taskId: widget.task.id,
            status: widget.task.status == taskDone ? taskTodo : taskDone,
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

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventActionsProvider)
          .deleteTask(eventId: widget.eventId, taskId: widget.task.id);
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(apiErrorMessage(widget.locale, err))),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final done = task.status == taskDone;

    return Opacity(
      opacity: _busy ? 0.6 : 1,
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            InkWell(
              onTap: _busy ? null : _toggle,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  done
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: done
                      ? context.mereytoiColors.goldPrimary
                      : context.mereytoiColors.textMuted,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done
                          ? context.mereytoiColors.textMuted
                          : context.mereytoiColors.textPrimary,
                    ),
                  ),
                  if (task.dueDate != null || task.assignee != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (task.dueDate != null)
                            formatMenuDate(task.dueDate!),
                          if (task.assignee != null) task.assignee!.name,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.canManage)
              IconButton(
                onPressed: _busy ? null : _delete,
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: context.mereytoiColors.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateTaskSheet extends ConsumerStatefulWidget {
  const _CreateTaskSheet({required this.eventId});

  final int eventId;

  @override
  ConsumerState<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends ConsumerState<_CreateTaskSheet> {
  final _controller = TextEditingController();
  DateTime? _dueDate;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(eventActionsProvider)
          .createTask(eventId: widget.eventId, title: title, dueDate: _dueDate);
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(ref.read(localeProvider), err);
          _submitting = false;
        });
      }
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
                  t(locale, ru: 'Новая задача', kz: 'Жаңа тапсырма'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Название задачи',
                      kz: 'Тапсырма атауы',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: t(
                        locale,
                        ru: 'Срок (необязательно)',
                        kz: 'Мерзімі (міндетті емес)',
                      ),
                    ),
                    child: Text(
                      _dueDate == null
                          ? t(locale, ru: 'Не выбран', kz: 'Таңдалмаған')
                          : formatMenuDate(_dueDate!),
                    ),
                  ),
                ),
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
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : Text(t(locale, ru: 'Добавить', kz: 'Қосу')),
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
