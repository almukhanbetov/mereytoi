import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import 'admin_labels.dart';
import 'admin_report_screen.dart';
import 'admin_widgets.dart';

/// The report queue — GET /api/admin/reports with a status filter, paged,
/// newest first.
class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({
    super.key,
    this.initialStatus = 'open',
    this.initialMine = false,
  });

  static const title = 'Жалобы';

  /// open | new | in_review | resolved | rejected | all
  final String initialStatus;
  final bool initialMine;

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

const _filters = <(String, bool, String)>[
  ('open', false, 'Открытые'),
  ('new', false, 'Новые'),
  ('in_review', false, 'В работе'),
  ('in_review', true, 'Мои'),
  ('resolved', false, 'Решённые'),
  ('rejected', false, 'Отклонённые'),
  ('all', false, 'Все'),
];

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  late String _status = widget.initialStatus;
  late bool _mine = widget.initialMine;
  // Part of the list's key: a filter change or a return from a report
  // rebuilds the list from page 1.
  int _tick = 0;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(adminServiceProvider);
    return AdminGate(
      title: AdminReportsScreen.title,
      child: Scaffold(
        appBar: AppBar(title: const Text(AdminReportsScreen.title)),
        body: Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (final (status, mine, label) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        key: ValueKey('admin-report-filter-$status-$mine'),
                        label: Text(label),
                        selected: _status == status && _mine == mine,
                        onSelected: (_) => setState(() {
                          _status = status;
                          _mine = mine;
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AdminPagedList<AdminReport>(
                key: ValueKey('reports-$_status-$_mine-$_tick'),
                fetch: (page) => service.reports(
                  status: _status == 'all' ? null : _status,
                  mine: _mine,
                  page: page,
                ),
                emptyText: 'Жалоб нет.',
                itemBuilder: (context, r) => AdminReportRow(
                  report: r,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AdminReportScreen(reportId: r.id),
                      ),
                    );
                    if (mounted) setState(() => _tick++);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminReportRow extends StatelessWidget {
  const AdminReportRow({super.key, required this.report, this.onTap});

  final AdminReport report;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final target = r.target.exists
        ? r.target.title
        : '${labelOf(reportTargetLabels, r.targetType)} удалён(а)';
    return AdminRowCard(
      key: ValueKey('admin-report-${r.id}'),
      title:
          '${labelOf(reportReasonLabels, r.reason)} · ${labelOf(reportTargetLabels, r.targetType)}',
      subtitle: [
        target,
        'от ${r.reporter?.name ?? '#${r.reporterId}'} · ${formatAdminDate(r.createdAt)}',
      ].join('\n'),
      onTap: onTap,
      pills: [
        AdminPill(
          labelOf(reportStatusLabels, r.status),
          tone: reportStatusTone(r.status),
        ),
        if (r.openOnSameTarget > 1)
          AdminPill(
            'Открытых на объект: ${r.openOnSameTarget}',
            tone: AdminTone.warn,
          ),
      ],
    );
  }
}
