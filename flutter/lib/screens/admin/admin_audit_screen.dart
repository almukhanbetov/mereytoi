import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import 'admin_user_screen.dart';
import 'admin_widgets.dart';

/// The administrators' action log — GET /api/admin/audit-events, newest
/// first, filtered by object type. Read-only.
class AdminAuditScreen extends ConsumerStatefulWidget {
  const AdminAuditScreen({super.key});

  static const title = 'Журнал действий';

  @override
  ConsumerState<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends ConsumerState<AdminAuditScreen> {
  String? _type;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(adminServiceProvider);
    return AdminGate(
      title: AdminAuditScreen.title,
      child: Scaffold(
        appBar: AppBar(title: const Text(AdminAuditScreen.title)),
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
                  for (final (type, label) in const <(String?, String)>[
                    (null, 'Все'),
                    ('user', 'Пользователи'),
                    ('listing', 'Карточки'),
                    ('report', 'Жалобы'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        key: ValueKey('admin-audit-filter-${type ?? 'all'}'),
                        label: Text(label),
                        selected: _type == type,
                        onSelected: (_) => setState(() => _type = type),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AdminPagedList<AdminAuditEvent>(
                key: ValueKey('audit-$_type'),
                fetch: (page) =>
                    service.auditEvents(targetType: _type, page: page),
                emptyText: 'Действий пока нет.',
                itemBuilder: (context, e) => GestureDetector(
                  onTap: e.targetType == 'user'
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminUserScreen(userId: e.targetId),
                          ),
                        )
                      : null,
                  child: AdminAuditRow(event: e, showTarget: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
