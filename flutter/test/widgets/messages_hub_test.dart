import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/screens/messages/messages_screen.dart';
import 'package:mereytoi_app/screens/provider_chat/provider_chat_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/widgets/chat/chat_fab.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptySecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => Future.value(false);
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
  }) => Future.value(null);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      Future.value(const {});
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

const _longName =
    'Очень длинное название ресторана с банкетным залом «Шаңырақ Гранд Палас» на 500 гостей';

/// Serves the two conversation lists plus the per-conversation GETs the
/// hub's rows open; records every request so tests can assert exactly
/// which endpoints were hit (and that a guest hits none).
class _FakeBackend implements HttpClientAdapter {
  _FakeBackend({
    this.managerUnread = 2,
    this.providerUnread = 1,
    this.empty = false,
  });

  final int managerUnread;
  final int providerUnread;
  final bool empty;
  final List<(String, String)> requests = [];

  static const _ts = '2026-01-01T10:00:00Z';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add((options.method, options.path));
    final path = options.path;
    Object data;
    if (path == '/api/manager-chat') {
      data = {
        'conversations': empty
            ? []
            : [
                {
                  'id': 12,
                  'user_id': 9,
                  'listing_id': 5,
                  'listing': {
                    'id': 5,
                    'name_ru': _longName,
                    'name_kz': 'Шаңырақ Гранд',
                    'price': 1000,
                  },
                  'status': 'open',
                  'created_at': _ts,
                  'updated_at': _ts,
                  'last_message': {
                    'id': 1,
                    'conversation_id': 12,
                    'sender_type': 'manager',
                    'body':
                        'Да, дата свободна — отправить смету на 500 гостей?',
                    'created_at': _ts,
                  },
                  'unread_count': managerUnread,
                },
                {
                  'id': 13,
                  'user_id': 9,
                  'status': 'open',
                  'created_at': _ts,
                  'updated_at': _ts,
                  'unread_count': 0,
                },
              ],
      };
    } else if (path == '/api/provider-chat') {
      data = {
        'conversations': empty
            ? []
            : [
                {
                  'id': 4,
                  'provider_id': 2,
                  'provider': {'display_name': 'Ерлан Events'},
                  'customer_user_id': 9,
                  'customer': {'display_name': 'Алия'},
                  'created_at': _ts,
                  'updated_at': _ts,
                  'last_message': {
                    'id': 1,
                    'conversation_id': 4,
                    'sender_user_id': 50,
                    'body': 'Добрый день!',
                    'created_at': _ts,
                  },
                  'unread_count': providerUnread,
                },
              ],
      };
    } else if (path == '/api/manager-chat/12' ||
        path == '/api/manager-chat/13') {
      final id = int.parse(path.split('/').last);
      data = {
        'conversation': {
          'id': id,
          'user_id': 9,
          'status': 'open',
          'created_at': _ts,
          'updated_at': _ts,
        },
        'messages': <Object>[],
      };
    } else if (path == '/api/provider-chat/4') {
      data = {
        'conversation': {
          'id': 4,
          'provider_id': 2,
          'customer_user_id': 9,
          'created_at': _ts,
          'updated_at': _ts,
        },
        'messages': <Object>[],
      };
    } else {
      throw StateError('unhandled fake route: ${options.method} $path');
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _user = User(
  id: 9,
  name: 'Алия',
  email: 'aliya@example.com',
  phone: '',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// A host page with a Scaffold whose FAB is the real [ChatFab] — same
/// placement RootShell uses, without pulling the four tabs' own data.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('HOME')),
    floatingActionButton: ChatFab(),
  );
}

Future<(ProviderContainer, _FakeBackend)> _pump(
  WidgetTester tester, {
  bool authenticated = true,
  _FakeBackend? backend,
  Widget home = const _Host(),
  ThemeData? theme,
  AppLocale locale = AppLocale.ru,
  Size size = const Size(393, 851),
}) async {
  FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = backend ?? _FakeBackend();
  final client = ApiClient.test(
    tokenProvider: () async => authenticated ? 'test-token' : null,
  );
  client.debugDio.httpClientAdapter = fake;
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: theme ?? AppTheme.dark, home: home),
    ),
  );
  await tester.pumpAndSettle();
  while (container.read(authProvider) is AuthLoading ||
      container.read(authProvider) is AuthInitial) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  container.read(localeProvider.notifier).setLocale(locale);
  if (authenticated) {
    container.read(authProvider.notifier).state = AuthAuthenticated(_user);
  }
  // Dio defers each request behind a zero-length timer, which
  // pumpAndSettle alone never advances — step the clock so the list
  // fetches actually complete before assertions.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
  return (container, fake);
}

Finder _badgeText(String text) =>
    find.descendant(of: find.byType(ChatFab), matching: find.text(text));

void main() {
  group('ChatFab', () {
    testWidgets('badge = manager unread + provider unread', (tester) async {
      await _pump(
        tester,
        backend: _FakeBackend(managerUnread: 2, providerUnread: 1),
      );
      expect(find.byType(ChatFab), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
      expect(_badgeText('3'), findsOneWidget);
    });

    testWidgets('no badge when nothing is unread', (tester) async {
      await _pump(
        tester,
        backend: _FakeBackend(managerUnread: 0, providerUnread: 0),
      );
      final badge = tester.widget<Badge>(
        find.descendant(of: find.byType(ChatFab), matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isFalse);
    });

    testWidgets('a guest sees the button, no badge, and no API call', (
      tester,
    ) async {
      final (_, fake) = await _pump(tester, authenticated: false);
      expect(find.byType(ChatFab), findsOneWidget);
      expect(fake.requests, isEmpty);
    });

    testWidgets(
      'tapping opens «Сообщения»; system back returns to the previous screen',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.byKey(const ValueKey('chat-fab')));
        await tester.pumpAndSettle();
        expect(find.byType(MessagesScreen), findsOneWidget);
        expect(find.text('Сообщения'), findsWidgets);

        await tester.binding.handlePopRoute(); // Android system back
        await tester.pumpAndSettle();
        expect(find.byType(MessagesScreen), findsNothing);
        expect(find.text('HOME'), findsOneWidget);
      },
    );
  });

  group('MessagesScreen', () {
    testWidgets('lists manager threads (with context) and provider threads', (
      tester,
    ) async {
      await _pump(tester, home: const MessagesScreen());
      expect(find.text('Менеджер MEREYTOI'), findsOneWidget);
      expect(find.text('Услугодатели'), findsOneWidget);
      expect(find.text(_longName), findsOneWidget); // service context
      expect(find.text('Общий вопрос'), findsOneWidget); // no-context thread
      expect(find.text('Ерлан Events'), findsOneWidget);
      expect(find.text('Добрый день!'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // manager row unread
      expect(find.text('1'), findsOneWidget); // provider row unread
    });

    testWidgets('empty state offers to message the manager', (tester) async {
      await _pump(
        tester,
        home: const MessagesScreen(),
        backend: _FakeBackend(empty: true),
      );
      expect(find.text('Пока нет обращений к менеджеру'), findsOneWidget);
      expect(find.text('Написать менеджеру'), findsOneWidget);
      expect(find.text('Пока нет переписок с услугодателями'), findsOneWidget);
    });

    testWidgets('guest: sign-in prompt, no 401, «Войти» opens login', (
      tester,
    ) async {
      final (_, fake) = await _pump(
        tester,
        home: const MessagesScreen(),
        authenticated: false,
      );
      expect(find.text('Войдите, чтобы видеть сообщения'), findsOneWidget);
      expect(fake.requests, isEmpty);
      await tester.tap(find.text('Войти'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
      'a manager row opens ManagerChatScreen by conversationId; back returns to the hub',
      (tester) async {
        final (container, fake) = await _pump(
          tester,
          home: const MessagesScreen(),
        );
        await tester.tap(find.text(_longName));
        await tester.pumpAndSettle();

        final screen = tester.widget<ManagerChatScreen>(
          find.byType(ManagerChatScreen),
        );
        expect(screen.conversationId, 12);
        expect(screen.chatContext.listingId, 5);
        expect(fake.requests, contains(('GET', '/api/manager-chat/12')));
        expect(
          fake.requests.where((r) => r.$2 == '/api/manager-chat/start'),
          isEmpty,
        );

        final listCallsBefore = fake.requests
            .where((r) => r.$2 == '/api/manager-chat')
            .length;
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(MessagesScreen), findsOneWidget);
        // Coming back re-fetches the lists so unread counts are fresh.
        expect(
          fake.requests.where((r) => r.$2 == '/api/manager-chat').length,
          greaterThan(listCallsBefore),
        );
        container
            .dispose(); // stop the chat's poll timer before the pending-timer check
      },
    );

    testWidgets('a provider row opens ProviderChatScreen by conversationId', (
      tester,
    ) async {
      final (container, fake) = await _pump(
        tester,
        home: const MessagesScreen(),
      );
      await tester.ensureVisible(find.text('Ерлан Events'));
      await tester.tap(find.text('Ерлан Events'));
      await tester.pumpAndSettle();

      final screen = tester.widget<ProviderChatScreen>(
        find.byType(ProviderChatScreen),
      );
      expect(screen.conversationId, 4);
      expect(screen.providerId, 2);
      expect(screen.peerName, 'Ерлан Events');
      expect(fake.requests, contains(('GET', '/api/provider-chat/4')));
      expect(
        fake.requests.where((r) => r.$2 == '/api/provider-chat/start'),
        isEmpty,
      );
      container.dispose();
    });

    for (final (locale, title, manager, providers, general) in [
      (
        AppLocale.ru,
        'Сообщения',
        'Менеджер MEREYTOI',
        'Услугодатели',
        'Общий вопрос',
      ),
      (
        AppLocale.kz,
        'Хабарламалар',
        'MEREYTOI менеджері',
        'Қызмет көрсетушілер',
        'Жалпы сұрақ',
      ),
      (
        AppLocale.en,
        'Messages',
        'MEREYTOI manager',
        'Service providers',
        'General question',
      ),
    ]) {
      testWidgets('localized: ${locale.name}', (tester) async {
        await _pump(tester, home: const MessagesScreen(), locale: locale);
        expect(find.text(title), findsOneWidget);
        expect(find.text(manager), findsOneWidget);
        expect(find.text(providers), findsOneWidget);
        expect(find.text(general), findsOneWidget);
      });
    }

    for (final name in ['dark', 'light']) {
      testWidgets('320dp wide, $name theme: hub has no overflow', (
        tester,
      ) async {
        final theme = name == 'dark' ? AppTheme.dark : AppTheme.light;
        await _pump(
          tester,
          home: const MessagesScreen(),
          theme: theme,
          size: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);
        expect(find.text(_longName), findsOneWidget);
      });

      testWidgets('320dp wide, $name theme: FAB + badge, no overflow', (
        tester,
      ) async {
        final theme = name == 'dark' ? AppTheme.dark : AppTheme.light;
        await _pump(tester, theme: theme, size: const Size(320, 640));
        expect(tester.takeException(), isNull);
        expect(_badgeText('3'), findsOneWidget);
      });
    }

    testWidgets('320dp guest prompt fits in every language', (tester) async {
      for (final locale in AppLocale.values) {
        await _pump(
          tester,
          home: const MessagesScreen(),
          authenticated: false,
          locale: locale,
          size: const Size(320, 568),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  test('messageTimeLabel: HH:mm today, dd.MM otherwise', () {
    final now = DateTime(2026, 9, 25, 18, 0);
    expect(messageTimeLabel(DateTime(2026, 9, 25, 9, 5), now: now), '09:05');
    expect(messageTimeLabel(DateTime(2026, 9, 3, 9, 5), now: now), '03.09');
  });
}
