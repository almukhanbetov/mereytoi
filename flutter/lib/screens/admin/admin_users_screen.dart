import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import 'admin_labels.dart';
import 'admin_user_screen.dart';
import 'admin_widgets.dart';

enum AdminUserFilter { all, providers, blocked }

/// People search: name, e-mail, phone or provider name; filters for
/// providers and blocked accounts. GET /api/admin/users, paged.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key, this.initialFilter = AdminUserFilter.all});

  static const title = 'Пользователи';

  final AdminUserFilter initialFilter;

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _search = TextEditingController();
  late AdminUserFilter _filter = widget.initialFilter;
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted && v.trim() != _query) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(adminServiceProvider);
    return AdminGate(
      title: AdminUsersScreen.title,
      child: Scaffold(
        appBar: AppBar(title: const Text(AdminUsersScreen.title)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: TextField(
                key: const ValueKey('admin-user-search'),
                controller: _search,
                onChanged: _onQuery,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => setState(() => _query = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Имя, e-mail, телефон, услугодатель',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                children: [
                  for (final (f, label) in const [
                    (AdminUserFilter.all, 'Все'),
                    (AdminUserFilter.providers, 'Услугодатели'),
                    (AdminUserFilter.blocked, 'Заблокированные'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: ChoiceChip(
                        key: ValueKey('admin-user-filter-${f.name}'),
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AdminPagedList<AdminUser>(
                key: ValueKey('users-$_query-${_filter.name}'),
                fetch: (page) => service.searchUsers(
                  query: _query,
                  provider: _filter == AdminUserFilter.providers ? true : null,
                  blocked: _filter == AdminUserFilter.blocked ? true : null,
                  page: page,
                ),
                emptyText: _query.isEmpty
                    ? 'Пока никого нет.'
                    : 'Никого не нашли по запросу «$_query».',
                itemBuilder: (context, u) => AdminUserRow(
                  user: u,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminUserScreen(userId: u.id),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminUserRow extends StatelessWidget {
  const AdminUserRow({super.key, required this.user, this.onTap});

  final AdminUser user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final contact = [
      user.email,
      if (user.phone.isNotEmpty) user.phone,
    ].join(' · ');
    return AdminRowCard(
      key: ValueKey('admin-user-${user.id}'),
      title: user.name.isEmpty ? 'Без имени' : user.name,
      subtitle: contact,
      onTap: onTap,
      pills: [
        if (user.isAdmin)
          const AdminPill('Администратор', tone: AdminTone.accent),
        if (user.provider != null)
          AdminPill('Услугодатель: ${user.provider!.displayName}'),
        if (user.isBlocked)
          AdminPill(
            user.block!.until == null
                ? 'Заблокирован бессрочно'
                : 'Заблокирован до ${formatAdminDate(user.block!.until)}',
            tone: AdminTone.bad,
          ),
        if (user.listingsCount > 0)
          AdminPill('Карточек: ${user.listingsCount}'),
      ],
    );
  }
}
