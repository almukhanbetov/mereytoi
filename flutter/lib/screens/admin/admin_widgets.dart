import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_skeleton.dart';
import 'admin_labels.dart';

/// Shows [child] only while the signed-in account is an administrator. The
/// moment that stops (role revoked, a 403 from the server, sign-out) every
/// admin screen turns into a closed notice instead of its content.
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(isAdminProvider)) return child;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        key: const ValueKey('admin-no-access'),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 40,
                color: context.mereytoiColors.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Доступ закрыт',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Раздел доступен только администраторам.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text('Вернуться'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Error body for an admin screen; when the error means the admin rights are
/// gone, it closes the panel instead of offering a retry.
class AdminErrorBody extends ConsumerWidget {
  const AdminErrorBody({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isAdminRightsLost(error)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => handleAdminRightsLost(ref, error),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              adminErrorText(error),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              key: const ValueKey('admin-retry'),
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminLoadingList extends StatelessWidget {
  const AdminLoadingList({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        for (var i = 0; i < count; i++) ...[
          const AppSkeleton(height: 72, borderRadius: AppRadius.lg),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      ),
    );
  }
}

enum AdminTone { neutral, good, warn, bad, accent }

/// A small status label. Text + tinted background, readable in both themes.
class AdminPill extends StatelessWidget {
  const AdminPill(this.label, {super.key, this.tone = AdminTone.neutral});

  final String label;
  final AdminTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.mereytoiColors;
    final color = switch (tone) {
      AdminTone.good => c.success,
      AdminTone.warn => c.warning,
      AdminTone.bad => c.error,
      AdminTone.accent => c.goldPrimary,
      AdminTone.neutral => c.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

AdminTone reportStatusTone(String status) => switch (status) {
  'new' => AdminTone.bad,
  'in_review' => AdminTone.warn,
  'resolved' => AdminTone.good,
  _ => AdminTone.neutral,
};

/// A tappable row card used across the admin lists.
class AdminRowCard extends StatelessWidget {
  const AdminRowCard({
    super.key,
    required this.title,
    this.subtitle,
    this.pills = const [],
    this.onTap,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> pills;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall,
                          ),
                        ],
                        if (pills.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Wrap(spacing: 6, runSpacing: 6, children: pills),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.mereytoiColors.textMuted,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A paged list: loads page 1, then «Показать ещё» for the next. Call
/// [AdminPagedListState.reload] (via a GlobalKey) after a change.
class AdminPagedList<T> extends ConsumerStatefulWidget {
  const AdminPagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    required this.emptyText,
    this.header,
  });

  final Future<AdminPage<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyText;
  final Widget? header;

  @override
  ConsumerState<AdminPagedList<T>> createState() => AdminPagedListState<T>();
}

class AdminPagedListState<T> extends ConsumerState<AdminPagedList<T>> {
  final _items = <T>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final page = await widget.fetch(_page + 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(page.items);
        _page = page.page;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      handleAdminRightsLost(ref, e);
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return AdminErrorBody(error: _error!, onRetry: reload);
    }
    if (_items.isEmpty && _loading) {
      return const AdminLoadingList();
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          ?widget.header,
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                widget.emptyText,
                key: const ValueKey('admin-empty'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (final item in _items) widget.itemBuilder(context, item),
          if (_hasMore && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: OutlinedButton(
                key: const ValueKey('admin-load-more'),
                onPressed: _loading ? null : _loadMore,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Показать ещё'),
              ),
            ),
          if (_error != null && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                adminErrorText(_error!),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.mereytoiColors.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the bottom sheet for an administrative action with a required
/// reason (3–1000 characters) and, for a block, a required term. [onSubmit]
/// performs it; the sheet stays open with the server's message on failure.
/// Returns true only after a successful submit.
Future<bool> showAdminActionSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required Future<void> Function(String reason, String? duration) onSubmit,
  bool danger = true,
  bool withDuration = false,
  String reasonHint = 'Причина (обязательно)',
  String? subjectName,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AdminActionSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      onSubmit: onSubmit,
      danger: danger,
      withDuration: withDuration,
      reasonHint: reasonHint,
      subjectName: subjectName,
    ),
  );
  return ok ?? false;
}

class AdminActionSheet extends ConsumerStatefulWidget {
  const AdminActionSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onSubmit,
    this.danger = true,
    this.withDuration = false,
    this.reasonHint = 'Причина (обязательно)',
    this.subjectName,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final Future<void> Function(String reason, String? duration) onSubmit;
  final bool danger;
  final bool withDuration;
  final String reasonHint;

  /// Who the block is for — shown in the summary above the confirm button.
  final String? subjectName;

  @override
  ConsumerState<AdminActionSheet> createState() => _AdminActionSheetState();
}

class _AdminActionSheetState extends ConsumerState<AdminActionSheet> {
  final _reason = TextEditingController();
  String? _duration;
  bool _submitting = false;
  bool _tried = false;
  String? _serverError;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String? get _reasonError {
    final n = _reason.text.trim().runes.length;
    if (n < 3) return 'Укажите причину — не короче 3 символов';
    if (n > 1000) return 'Не длиннее 1000 символов';
    return null;
  }

  bool get _valid =>
      _reasonError == null && (!widget.withDuration || _duration != null);

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _tried = true);
    if (!_valid) return;
    setState(() {
      _submitting = true;
      _serverError = null;
    });
    try {
      await widget.onSubmit(_reason.text.trim(), _duration);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      if (handleAdminRightsLost(ref, e)) {
        Navigator.of(context).pop(false);
        return;
      }
      setState(() {
        _submitting = false;
        _serverError = adminErrorText(e);
      });
    }
  }

  bool get _isPermanent => widget.withDuration && _duration == 'permanent';

  /// A term chip. «Бессрочно» stands out when chosen: error-tinted, with a
  /// warning icon instead of the checkmark. The choice is kept in state, so
  /// failed validation or a server refusal never resets it.
  Widget _durationChip(String code, String label, MereytoiColors colors) {
    final selected = _duration == code;
    final permanent = code == 'permanent';
    return ChoiceChip(
      key: ValueKey('admin-duration-$code'),
      label: Text(label),
      selected: selected,
      showCheckmark: !permanent,
      avatar: permanent && selected
          ? Icon(Icons.warning_amber_rounded, size: 18, color: colors.error)
          : null,
      selectedColor: permanent ? colors.error.withValues(alpha: 0.16) : null,
      side: permanent && selected ? BorderSide(color: colors.error) : null,
      labelStyle: permanent && selected
          ? TextStyle(color: colors.error, fontWeight: FontWeight.w700)
          : null,
      onSelected: _submitting ? null : (_) => setState(() => _duration = code),
    );
  }

  /// «Проверьте перед блокировкой»: who, for how long, why. An indefinite
  /// block gets an error-coloured frame and its own warning line.
  Widget _blockSummary(MereytoiColors colors, TextTheme textTheme) {
    String term;
    if (_duration == null) {
      term = 'не выбран';
    } else {
      final label = blockDurations.firstWhere((d) => d.$1 == _duration).$2;
      final days = switch (_duration) {
        '1d' => 1,
        '7d' => 7,
        '30d' => 30,
        _ => 0,
      };
      term = days == 0
          ? label
          : '$label — до ~${formatAdminDate(DateTime.now().add(Duration(days: days)))}';
    }
    final reason = _reason.text.trim();
    final frame = _isPermanent ? colors.error : colors.border;
    Widget line(String k, String v, {Key? key, Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        key: key,
        TextSpan(
          children: [
            TextSpan(
              text: '$k: ',
              style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
            TextSpan(
              text: v,
              style: textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
    return Container(
      key: const ValueKey('admin-block-summary'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _isPermanent
            ? colors.error.withValues(alpha: 0.10)
            : colors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: frame, width: _isPermanent ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Проверьте перед блокировкой', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          line(
            'Пользователь',
            (widget.subjectName ?? '').isEmpty ? '—' : widget.subjectName!,
          ),
          line(
            'Срок',
            term,
            key: const ValueKey('admin-summary-term'),
            color: _isPermanent ? colors.error : null,
          ),
          line(
            'Причина',
            reason.isEmpty ? 'не указана' : reason,
            key: const ValueKey('admin-summary-reason'),
          ),
          if (_isPermanent) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              key: const ValueKey('admin-summary-permanent'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: colors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Бессрочная блокировка — без даты окончания. Снять её '
                    'можно только вручную.',
                    style: textTheme.bodySmall?.copyWith(color: colors.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final accent = widget.danger ? colors.error : colors.goldPrimary;
    return PopScope(
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(widget.title, style: textTheme.titleMedium),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                widget.message,
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (widget.withDuration) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Срок', style: textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final (code, label) in blockDurations)
                      _durationChip(code, label, colors),
                  ],
                ),
                if (_tried && _duration == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Выберите срок',
                      style: textTheme.bodySmall?.copyWith(color: colors.error),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('admin-reason'),
                controller: _reason,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: widget.reasonHint,
                  errorText: _tried ? _reasonError : null,
                  errorMaxLines: 2,
                ),
              ),
              if (_serverError != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _serverError!,
                  key: const ValueKey('admin-sheet-error'),
                  style: textTheme.bodySmall?.copyWith(color: colors.error),
                ),
              ],
              if (widget.withDuration) ...[
                const SizedBox(height: AppSpacing.md),
                _blockSummary(colors, textTheme),
              ],
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                key: const ValueKey('admin-confirm'),
                onPressed: _submitting ? null : _submit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  disabledForegroundColor: accent,
                  side: BorderSide(color: accent),
                ),
                child: _submitting
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Text(
                        _isPermanent
                            ? '${widget.confirmLabel} бессрочно'
                            : widget.confirmLabel,
                      ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                key: const ValueKey('admin-cancel'),
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Отмена'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain confirmation without a reason (e.g. taking a report into work).
/// Returns true on confirm; Back, outside tap and «Отмена» return false.
Future<bool> showAdminConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useSafeArea: true,
    builder: (ctx) {
      var decided = false;
      void close(bool v) {
        if (decided) return;
        decided = true;
        Navigator.of(ctx).pop(v);
      }

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: Theme.of(ctx).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              key: const ValueKey('admin-confirm-yes'),
              onPressed: () => close(true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              key: const ValueKey('admin-confirm-no'),
              onPressed: () => close(false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}

void showAdminSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
