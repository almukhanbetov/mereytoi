import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/account_block.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/models/user_report.dart';
import 'package:mereytoi_app/screens/auth/account_blocked_screen.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/profile/my_reports_screen.dart';
import 'package:mereytoi_app/screens/profile/provider/my_services_screen.dart';
import 'package:mereytoi_app/services/auth_service.dart';
import 'package:mereytoi_app/services/report_service.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/core/storage/locale_storage.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/report_providers.dart';
import 'package:mereytoi_app/widgets/report/report_sheet.dart';

class _Storage extends FlutterSecureStoragePlatform {
  _Storage(this.token);
  final String? token;
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => token != null;
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
  }) async => token;
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

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

class _MemLocale implements LocaleStorage {
  _MemLocale(this.value);
  AppLocale value;
  @override
  Future<AppLocale?> read() async => value;
  @override
  Future<void> write(AppLocale locale) async => value = locale;
}

ApiClient _client() => ApiClient.test(tokenProvider: () async => 'token');

class _FakeAuth extends AuthService {
  _FakeAuth() : super(_client());
  @override
  Future<AuthResult> login({
    String? email,
    String? phone,
    required String password,
  }) async => throw const ApiException(
    ApiErrorType.forbidden,
    statusCode: 403,
    debugMessage: 'account_blocked',
    data: {
      'error': 'account_blocked',
      'reason': 'Мошенничество',
      'blocked_until': '2026-12-01T10:00:00Z',
    },
  );
}

class _FakeReports extends ReportService {
  _FakeReports() : super(_client());
  final sent = <String>[];
  Object? failWith;
  Completer<void>? gate;
  List<UserReport> list = const [];

  @override
  Future<void> create({
    required String targetType,
    required int targetId,
    required String reason,
    String details = '',
  }) async {
    sent.add('$targetType:$targetId:$reason:$details');
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
  }

  @override
  Future<List<UserReport>> mine() async => list;
}

void main() {
  late _FakeReports reports;

  setUp(() {
    reports = _FakeReports();
    FlutterSecureStoragePlatform.instance = _Storage(null);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    ThemeData? theme,
    AppLocale locale = AppLocale.ru,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A fresh tree each time: a reused ProviderScope would keep its state.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(_FakeAuth()),
          reportServiceProvider.overrideWithValue(reports),
          localeProvider.overrideWith(
            (ref) => LocaleNotifier(_MemLocale(locale)),
          ),
        ],
        child: MaterialApp(theme: theme ?? AppTheme.light, home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('401 routing', () {
    test(
      'account_blocked goes to the blocked handler, not a plain sign-out',
      () async {
        final client = ApiClient.test(tokenProvider: () async => 't');
        client.debugDio.httpClientAdapter = _Adapter(401, {
          'error': 'account_blocked',
          'reason': 'Спам',
          'blocked_until': null,
        });
        var plain = 0;
        Map<String, dynamic>? blocked;
        client.setUnauthorizedHandler(() => plain++);
        client.setAccountBlockedHandler((b) => blocked = b);
        await expectLater(
          client.getJson('/api/auth/me'),
          throwsA(isA<ApiException>()),
        );
        expect(plain, 0);
        expect(blocked?['reason'], 'Спам');
        final block = AccountBlock.fromJson(blocked!);
        expect(block.indefinite, isTrue);
      },
    );

    test('an ordinary 401 still signs out', () async {
      final client = ApiClient.test(tokenProvider: () async => 't');
      client.debugDio.httpClientAdapter = _Adapter(401, {
        'error': 'session_expired',
      });
      var plain = 0;
      var blocked = 0;
      client.setUnauthorizedHandler(() => plain++);
      client.setAccountBlockedHandler((_) => blocked++);
      await expectLater(client.getJson('/api/x'), throwsA(isA<ApiException>()));
      expect((plain, blocked), (1, 0));
    });

    test('a 403 account_blocked carries its body for the screens', () async {
      final client = ApiClient.test(tokenProvider: () async => null);
      client.debugDio.httpClientAdapter = _Adapter(403, {
        'error': 'account_blocked',
        'reason': 'Оскорбления',
        'blocked_until': '2026-12-01T10:00:00Z',
        'password_reset': true,
        'recovery_code': 'ABCD-EFGH',
      });
      try {
        await client.postJson('/api/auth/recovery/reset', {});
        fail('expected an error');
      } catch (e) {
        final b = accountBlockFrom(e)!;
        expect(b.reason, 'Оскорбления');
        expect(b.until, isNotNull);
        expect(b.passwordReset, isTrue);
        expect(b.recoveryCode, 'ABCD-EFGH');
      }
    });
  });

  testWidgets('blocked screen: term, reason, new backup code; RU/KZ/EN', (
    tester,
  ) async {
    final block = AccountBlock.fromJson({
      'reason': 'Мошенничество',
      'blocked_until': '2026-12-01T10:00:00Z',
      'password_reset': true,
      'recovery_code': 'ABCD-EFGH-IJKL',
    });
    await pump(tester, AccountBlockedScreen(block: block));
    expect(find.text('Аккаунт заблокирован'), findsOneWidget);
    expect(find.textContaining('До 01.12.2026'), findsOneWidget);
    expect(find.text('Мошенничество'), findsOneWidget);
    expect(find.text('ABCD-EFGH-IJKL'), findsOneWidget);
    await pump(
      tester,
      AccountBlockedScreen(block: block),
      locale: AppLocale.kz,
    );
    expect(find.text('Аккаунт бұғатталған'), findsOneWidget);
    expect(find.textContaining('дейін'), findsOneWidget);
    await pump(
      tester,
      const AccountBlockedScreen(block: AccountBlock(reason: 'Spam')),
      locale: AppLocale.en,
    );
    expect(find.text('Your account is blocked'), findsOneWidget);
    expect(find.text('Indefinite'), findsOneWidget);
    expect(find.byKey(const ValueKey('account-blocked-code')), findsNothing);
  });

  testWidgets('blocked sign-in opens the blocked screen, no raw code', (
    tester,
  ) async {
    await pump(tester, const LoginScreen());
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'user@test.kz');
    await tester.enterText(fields.at(1), 'password123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Войти'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-blocked')), findsOneWidget);
    expect(find.text('Мошенничество'), findsOneWidget);
    expect(find.textContaining('account_blocked'), findsNothing);
    expect(find.textContaining('Недостаточно прав'), findsNothing);
  });

  Future<void> openSheet(WidgetTester tester) async {
    await pump(
      tester,
      const Scaffold(
        body: ReportSheet(
          targetType: 'listing',
          targetId: 44,
          targetName: 'Ведущий Ерлан',
        ),
      ),
    );
  }

  testWidgets('report: reason required, «Другое» needs details, '
      'confirm before send, sent once', (tester) async {
    await openSheet(tester);
    expect(find.textContaining('«Ведущий Ерлан»'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-reason-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('report-reason-other')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('report-next')));
    await tester.pumpAndSettle();
    expect(
      find.text('Опишите проблему — не короче 5 символов.'),
      findsOneWidget,
    );
    expect(reports.sent, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('report-details')),
      'Выдаёт себя за другое агентство',
    );
    await tester.tap(find.byKey(const ValueKey('report-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-summary')), findsOneWidget);
    expect(find.text('Причина: Другое'), findsOneWidget);
    expect(reports.sent, isEmpty);

    reports.gate = Completer<void>();
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('report-send')),
      warnIfMissed: false,
    );
    reports.gate!.complete();
    await tester.pumpAndSettle();
    expect(reports.sent, ['listing:44:other:Выдаёт себя за другое агентство']);
    expect(find.byKey(const ValueKey('report-sent')), findsOneWidget);
  });

  testWidgets('a repeated report is explained, not an error', (tester) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
    await tester.tap(find.byKey(const ValueKey('report-next')));
    await tester.pumpAndSettle();
    reports.failWith = const ApiException(
      ApiErrorType.conflict,
      statusCode: 409,
      debugMessage: 'duplicate_report',
    );
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-duplicate')), findsOneWidget);
    expect(find.textContaining('Вы уже пожаловались'), findsOneWidget);
  });

  testWidgets('rate limit and own listing are explained in words', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
    await tester.tap(find.byKey(const ValueKey('report-next')));
    await tester.pumpAndSettle();
    reports.failWith = const ApiException(
      ApiErrorType.unknown,
      statusCode: 429,
      debugMessage: 'too_many_reports',
    );
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Слишком много жалоб'), findsOneWidget);
    reports.failWith = const ApiException(
      ApiErrorType.unknown,
      statusCode: 400,
      debugMessage: 'cannot_report_self',
    );
    await tester.tap(find.byKey(const ValueKey('report-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Нельзя пожаловаться на себя'), findsOneWidget);
  });

  testWidgets('a guest is asked to sign in instead of the form', (
    tester,
  ) async {
    await pump(
      tester,
      const Scaffold(
        body: ReportButton(
          targetType: 'provider',
          targetId: 3,
          targetName: 'X',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('report-provider-3')));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(reports.sent, isEmpty);
  });

  testWidgets('«Мои жалобы»: statuses in words, empty state', (tester) async {
    await pump(tester, const MyReportsScreen());
    expect(find.byKey(const ValueKey('my-reports-empty')), findsOneWidget);
    reports.list = [
      UserReport.fromJson({
        'id': 1,
        'target_type': 'listing',
        'target_id': 44,
        'target_title': 'Ведущий Ерлан',
        'reason': 'fraud',
        'status': 'in_review',
        'created_at': '2026-11-17T10:00:00Z',
      }),
      UserReport.fromJson({
        'id': 2,
        'target_type': 'provider',
        'target_id': 3,
        'target_title': 'Тойхана',
        'reason': 'abuse',
        'status': 'resolved',
        'created_at': '2026-11-16T10:00:00Z',
        'resolved_at': '2026-11-17T10:00:00Z',
      }),
    ];
    for (final (locale, review, done) in [
      (AppLocale.ru, 'На рассмотрении', 'Рассмотрена'),
      (AppLocale.kz, 'Қаралуда', 'Қаралды'),
      (AppLocale.en, 'Under review', 'Reviewed'),
    ]) {
      await pump(tester, const MyReportsScreen(), locale: locale);
      expect(find.text(review), findsOneWidget, reason: '$locale');
      expect(find.text(done), findsOneWidget, reason: '$locale');
      expect(find.text('Ведущий Ерлан'), findsOneWidget);
    }
  });

  testWidgets('owner sees why a listing is hidden by an administrator', (
    tester,
  ) async {
    final listing = Listing.fromJson({
      'id': 9,
      'category_id': 2,
      'name_ru': 'Шоу',
      'name_kz': 'Шоу',
      'is_active': true,
      'moderation_hidden_at': '2026-11-17T10:00:00Z',
      'moderation_reason': 'Чужие фото',
    });
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await pump(
        tester,
        Scaffold(
          body: AdminHiddenNote(listing: listing, locale: AppLocale.ru),
        ),
        theme: theme,
        width: 320,
      );
      expect(find.text('Скрыта администратором'), findsOneWidget);
      expect(find.text('Причина: Чужие фото'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('report sheet and blocked screen fit 320dp, light and dark, '
      'RU/KZ/EN', (tester) async {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      for (final locale in AppLocale.values) {
        await pump(
          tester,
          const Scaffold(
            body: ReportSheet(
              targetType: 'provider',
              targetId: 3,
              targetName: 'Очень длинное название услугодателя для проверки',
            ),
          ),
          theme: theme,
          locale: locale,
          width: 320,
        );
        expect(tester.takeException(), isNull, reason: '$locale');
        await pump(
          tester,
          AccountBlockedScreen(
            block: AccountBlock(reason: 'Длинная причина ' * 8),
          ),
          theme: theme,
          locale: locale,
          width: 320,
        );
        expect(tester.takeException(), isNull, reason: '$locale');
      }
    }
  });
}
