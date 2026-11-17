import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/admin.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/admin/admin_home_screen.dart';
import 'package:mereytoi_app/screens/admin/admin_report_screen.dart';
import 'package:mereytoi_app/screens/admin/admin_user_screen.dart';
import 'package:mereytoi_app/screens/admin/admin_users_screen.dart';
import 'package:mereytoi_app/services/admin_service.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/state/admin_providers.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Secure storage that already holds a session token, so AuthNotifier
/// restores a session through the fake AuthService below.
class _TokenStorage extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => true;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => 'token';
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => const {};
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

ApiClient _client() => ApiClient.test(tokenProvider: () async => 'token');

class _FakeAuth extends AuthService {
  _FakeAuth(this.role) : super(_client());
  String role;

  @override
  Future<User> fetchMe() async => User.fromJson({
    'id': 1,
    'name': 'Admin',
    'email': 'admin@test',
    'role': role,
  });
}

const _rightsLost = ApiException(
  ApiErrorType.forbidden,
  statusCode: 403,
  debugMessage: 'admin access required',
);

class _FakeAdmin extends AdminService {
  _FakeAdmin() : super(_client());

  final calls = <String>[];
  Object? failWith;
  Completer<void>? gate;
  AdminUser target = _user(blocked: false);
  AdminReport currentReport = _report('new');

  static AdminUser _user({required bool blocked, String role = 'user'}) =>
      AdminUser.fromJson({
        'id': 7,
        'name': 'Ерлан Тест',
        'email': 'erlan@test',
        'phone': '+77001112233',
        'role': role,
        'status': 'active',
        'listings_count': 1,
        'provider': {
          'id': 3,
          'display_name': 'Ерлан Events',
          'status': 'active',
        },
        if (blocked)
          'block': {
            'active': true,
            'until': '2026-12-01T00:00:00Z',
            'reason': 'Жалобы',
          },
      });

  static AdminReport _report(String status) => AdminReport.fromJson({
    'id': 5,
    'reporter_id': 9,
    'target_type': 'listing',
    'target_id': 44,
    'target_user_id': 7,
    'reason': 'fraud',
    'details': 'Просит предоплату',
    'status': status,
    'reporter': {'id': 9, 'name': 'Заявитель', 'email': 'r@test'},
    'target_user': {'id': 7, 'name': 'Ерлан Тест'},
    'target': {
      'exists': true,
      'title': 'Ведущий Ерлан',
      'detail': {'is_active': true, 'publicly_visible': true},
    },
    'open_on_same_target': 1,
  });

  Future<void> _act(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<AdminSummary> summary() async {
    if (failWith != null) throw failWith!;
    return AdminSummary.fromJson({
      'reports_new': 3,
      'reports_in_review': 1,
      'reports_mine': 1,
      'reviews_pending': 2,
      'blocked_users': 1,
      'hidden_listings': 0,
    });
  }

  @override
  Future<AdminPage<AdminUser>> searchUsers({
    String query = '',
    bool? provider,
    bool? blocked,
    int page = 1,
  }) async {
    calls.add('search:$query:${blocked ?? ''}');
    if (failWith != null) throw failWith!;
    return AdminPage(items: [target], total: 1, page: 1, perPage: 20);
  }

  @override
  Future<AdminUserDetail> user(int id) async {
    if (failWith != null && calls.isEmpty) throw failWith!;
    return AdminUserDetail(
      user: target,
      listings: [
        AdminListing.fromJson({
          'id': 44,
          'category_id': 2,
          'name_ru': 'Ведущий Ерлан',
          'role': 'owner',
          'is_active': true,
          'publicly_visible': true,
        }),
      ],
      history: const [],
    );
  }

  @override
  Future<void> block(int userId, String reason, String duration) =>
      _act('block:$userId:$reason:$duration');

  @override
  Future<void> warn(int userId, String reason) => _act('warn:$userId:$reason');

  @override
  Future<void> hideListing(int listingId, String reason) =>
      _act('hide:$listingId:$reason');

  @override
  Future<AdminReportDetail> report(int id) async => AdminReportDetail(
    report: currentReport,
    related: const [],
    history: const [],
  );

  @override
  Future<void> takeReport(int id) => _act('take:$id');

  @override
  Future<void> decideReport(int id, String decision, String reason) =>
      _act('decide:$id:$decision:$reason');
}

void main() {
  late _FakeAuth auth;
  late _FakeAdmin admin;

  setUp(() {
    FlutterSecureStoragePlatform.instance = _TokenStorage();
    auth = _FakeAuth('admin');
    admin = _FakeAdmin();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    ThemeData? theme,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(auth),
          adminServiceProvider.overrideWithValue(admin),
        ],
        child: MaterialApp(theme: theme ?? AppTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('non-admin sees a closed notice, not the panel', (tester) async {
    auth.role = 'user';
    await pump(tester, const AdminHomeScreen());
    expect(find.byKey(const ValueKey('admin-no-access')), findsOneWidget);
    expect(find.text('Новые жалобы'), findsNothing);
  });

  testWidgets('admin home shows the summary and opens sections', (
    tester,
  ) async {
    await pump(tester, const AdminHomeScreen());
    expect(find.text('Новые жалобы'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-tile-blocked')));
    await tester.pumpAndSettle();
    expect(find.text(AdminUsersScreen.title), findsOneWidget);
    expect(admin.calls, contains('search::true'));
  });

  testWidgets('losing admin rights closes the open screen', (tester) async {
    await pump(tester, const AdminUsersScreen());
    expect(find.text('Ерлан Тест'), findsOneWidget);
    // The role is revoked on the server: the next admin call gets 403 and
    // /auth/me now says "user".
    auth.role = 'user';
    admin.failWith = _rightsLost;
    await tester.enterText(
      find.byKey(const ValueKey('admin-user-search')),
      'x',
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-no-access')), findsOneWidget);
    expect(find.text('Ерлан Тест'), findsNothing);
  });

  testWidgets('block needs a reason and a term, submits once', (tester) async {
    await pump(tester, const AdminUserScreen(userId: 7));
    await tester.tap(find.byKey(const ValueKey('admin-block')));
    await tester.pumpAndSettle();

    // Nothing sent without a reason and a term.
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Выберите срок'), findsOneWidget);
    expect(find.text('Укажите причину — не короче 3 символов'), findsOneWidget);
    expect(admin.calls.where((c) => c.startsWith('block')), isEmpty);

    await tester.tap(find.byKey(const ValueKey('admin-duration-7d')));
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason')),
      'Мошенничество',
    );
    admin.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pump();
    // A second tap while the first is in flight does nothing.
    await tester.tap(
      find.byKey(const ValueKey('admin-confirm')),
      warnIfMissed: false,
    );
    await tester.pump();
    admin.gate!.complete();
    await tester.pumpAndSettle();
    expect(admin.calls.where((c) => c.startsWith('block')).toList(), [
      'block:7:Мошенничество:7d',
    ]);
    expect(find.text('Пользователь заблокирован'), findsOneWidget);
  });

  testWidgets('cancel sends nothing; a server refusal stays in the sheet', (
    tester,
  ) async {
    await pump(tester, const AdminUserScreen(userId: 7));
    await tester.tap(find.byKey(const ValueKey('admin-warn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-cancel')));
    await tester.pumpAndSettle();
    expect(admin.calls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('admin-block')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-duration-1d')));
    await tester.enterText(find.byKey(const ValueKey('admin-reason')), 'Тест');
    admin.failWith = const ApiException(
      ApiErrorType.forbidden,
      statusCode: 403,
      debugMessage: 'cannot_block_admin',
    );
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Нельзя заблокировать администратора.'), findsOneWidget);
    // An ordinary 403 is not a loss of rights: the panel stays open.
    expect(find.byKey(const ValueKey('admin-no-access')), findsNothing);
  });

  testWidgets('no block button for an administrator or a blocked user', (
    tester,
  ) async {
    admin.target = _FakeAdmin._user(blocked: false, role: 'admin');
    await pump(tester, const AdminUserScreen(userId: 7));
    expect(find.byKey(const ValueKey('admin-block')), findsNothing);
    admin.target = _FakeAdmin._user(blocked: true);
    await pump(tester, const AdminUserScreen(userId: 8));
    expect(find.byKey(const ValueKey('admin-block')), findsNothing);
    expect(find.byKey(const ValueKey('admin-unblock')), findsOneWidget);
    expect(find.text('Причина: Жалобы'), findsOneWidget);
  });

  testWidgets('hiding a listing asks for a reason', (tester) async {
    await pump(tester, const AdminUserScreen(userId: 7));
    await tester.ensureVisible(
      find.byKey(const ValueKey('admin-listing-toggle-44')),
    );
    await tester.tap(find.byKey(const ValueKey('admin-listing-toggle-44')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('admin-reason')), 'Фейк');
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['hide:44:Фейк']);
  });

  testWidgets('report: take with confirmation, decide with a reason', (
    tester,
  ) async {
    await pump(tester, const AdminReportScreen(reportId: 5));
    expect(find.text('Ведущий Ерлан'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin-report-take')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-confirm-no')));
    await tester.pumpAndSettle();
    expect(admin.calls, isEmpty);
    await tester.tap(find.byKey(const ValueKey('admin-report-take')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-confirm-yes')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['take:5']);

    await tester.ensureVisible(
      find.byKey(const ValueKey('admin-report-reject')),
    );
    await tester.tap(find.byKey(const ValueKey('admin-report-reject')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(admin.calls, ['take:5']);
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason')),
      'Нарушения нет',
    );
    admin.failWith = const ApiException(
      ApiErrorType.conflict,
      statusCode: 409,
      debugMessage: 'already_decided',
    );
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'decide:5:rejected:Нарушения нет');
    expect(find.text('По жалобе уже принято решение.'), findsOneWidget);
  });

  testWidgets('decided report has no decision buttons', (tester) async {
    admin.currentReport = _FakeAdmin._report('resolved');
    await pump(tester, const AdminReportScreen(reportId: 5));
    expect(find.byKey(const ValueKey('admin-report-take')), findsNothing);
    expect(find.byKey(const ValueKey('admin-report-resolve')), findsNothing);
  });

  testWidgets('320dp, light and dark: no overflow on the main screens', (
    tester,
  ) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final screen in const <Widget>[
        AdminHomeScreen(),
        AdminUsersScreen(),
        AdminUserScreen(userId: 7),
        AdminReportScreen(reportId: 5),
      ]) {
        await pump(tester, screen, theme: theme, width: 320);
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    }
  });

  testWidgets('block summary: user, term, reason; term survives errors; '
      'indefinite is highlighted', (tester) async {
    await pump(tester, const AdminUserScreen(userId: 7));
    await tester.tap(find.byKey(const ValueKey('admin-block')));
    await tester.pumpAndSettle();

    bool selected(String code) => tester
        .widget<ChoiceChip>(find.byKey(ValueKey('admin-duration-$code')))
        .selected;
    String summary(String key) => tester
        .widget<Text>(find.byKey(ValueKey('admin-summary-$key')))
        .textSpan!
        .toPlainText();

    final s = find.byKey(const ValueKey('admin-block-summary'));
    expect(s, findsOneWidget);
    expect(
      find.descendant(of: s, matching: find.textContaining('Ерлан Тест')),
      findsOneWidget,
    );
    expect(summary('term'), contains('не выбран'));
    expect(summary('reason'), contains('не указана'));

    // Pick 7 days, submit without a reason: error shown, term kept.
    await tester.tap(find.byKey(const ValueKey('admin-duration-7d')));
    await tester.pump();
    expect(summary('term'), contains('7 дней — до ~'));
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Укажите причину — не короче 3 символов'), findsOneWidget);
    expect(selected('7d'), isTrue);
    expect(summary('term'), contains('7 дней'));
    expect(admin.calls, isEmpty);

    // A server refusal keeps it too.
    await tester.enterText(
      find.byKey(const ValueKey('admin-reason')),
      'Спам в чате',
    );
    await tester.pump();
    expect(summary('reason'), contains('Спам в чате'));
    admin.failWith = const ApiException(ApiErrorType.server, statusCode: 500);
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin-sheet-error')), findsOneWidget);
    expect(selected('7d'), isTrue);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('admin-reason')))
          .controller!
          .text,
      'Спам в чате',
    );

    // Indefinite: warning in the summary, the chip and the button say so.
    expect(find.byKey(const ValueKey('admin-summary-permanent')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-duration-permanent')));
    await tester.pump();
    expect(selected('permanent'), isTrue);
    expect(selected('7d'), isFalse);
    expect(summary('term'), 'Срок: Бессрочно');
    expect(
      find.byKey(const ValueKey('admin-summary-permanent')),
      findsOneWidget,
    );
    expect(find.text('Заблокировать бессрочно'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('admin-duration-permanent')),
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );

    admin.failWith = null;
    await tester.tap(find.byKey(const ValueKey('admin-confirm')));
    await tester.pumpAndSettle();
    expect(admin.calls.last, 'block:7:Спам в чате:permanent');
  });

  testWidgets('block sheet fits 320dp in both themes', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pump(
        tester,
        const AdminUserScreen(userId: 7),
        theme: theme,
        width: 320,
      );
      await tester.tap(find.byKey(const ValueKey('admin-block')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admin-duration-permanent')));
      await tester.enterText(
        find.byKey(const ValueKey('admin-reason')),
        'Очень длинная причина блокировки ' * 6,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Заблокировать бессрочно'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('admin-cancel')));
      await tester.tap(find.byKey(const ValueKey('admin-cancel')));
      await tester.pumpAndSettle();
    }
    expect(admin.calls, isEmpty);
  });
}
