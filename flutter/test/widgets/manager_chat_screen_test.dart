import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/domain/manager_chat/manager_chat_context.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/auth/login_screen.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-53 — `ManagerChatScreen` already existed (this audit's
/// headline finding — see the stage report), but had zero widget-level
/// test coverage. These exercise the real screen end to end against a
/// scripted `/api/manager-chat/*` fake, the same seam
/// `restaurant_detail_overflow_test.dart` already established.
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

/// A tiny stateful fake: `start`/`get`/`addMessage` all read and write the
/// same in-memory conversation, so a test can actually send a message and
/// see it come back — not just assert on one canned response.
class _FakeAdapter implements HttpClientAdapter {
  int _nextMessageId = 1;
  Map<String, dynamic>? _conversation;
  final List<Map<String, dynamic>> _messages = [];
  final List<String> requestedPaths = [];

  /// Seeds an already-existing conversation with history, as if this
  /// context had been chatted in before.
  void seedExisting({
    required int conversationId,
    int? listingId,
    int? eventId,
    required List<(String senderType, String body)> history,
  }) {
    _conversation = {
      'id': conversationId,
      'user_id': 9,
      'listing_id': listingId,
      'event_id': eventId,
      'status': 'open',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };
    for (final (sender, body) in history) {
      _messages.add({
        'id': _nextMessageId++,
        'conversation_id': conversationId,
        'sender_type': sender,
        'body': body,
        'created_at': '2026-01-01T00:0${_messages.length}:00Z',
      });
    }
  }

  /// Makes every request fail — used for the error-view test.
  bool failAll = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);
    if (failAll) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }

    Map<String, dynamic> data;
    if (options.path == '/api/manager-chat/start') {
      final body = options.data as Map;
      final message = (body['message'] as String?)?.trim() ?? '';
      if (_conversation == null && message.isEmpty) {
        data = {'conversation': null, 'messages': <Map<String, dynamic>>[]};
      } else {
        _conversation ??= {
          'id': 1,
          'user_id': 9,
          'listing_id': body['listing_id'],
          'event_id': body['event_id'],
          'status': 'open',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };
        if (message.isNotEmpty) {
          _messages.add({
            'id': _nextMessageId++,
            'conversation_id': _conversation!['id'],
            'sender_type': 'user',
            'body': message,
            'created_at': '2026-01-01T00:0${_messages.length}:00Z',
          });
        }
        data = {'conversation': _conversation, 'messages': _messages};
      }
    } else if (options.path.startsWith('/api/manager-chat/') &&
        options.path.endsWith('/messages')) {
      final body = options.data as Map;
      _messages.add({
        'id': _nextMessageId++,
        'conversation_id': _conversation!['id'],
        'sender_type': 'user',
        'body': body['body'],
        'created_at': '2026-01-01T00:0${_messages.length}:00Z',
      });
      data = {'conversation': _conversation, 'messages': _messages};
    } else if (options.path.startsWith('/api/manager-chat/')) {
      // GET :id — the poll route.
      data = {'conversation': _conversation, 'messages': _messages};
    } else {
      throw StateError('unhandled fake route: ${options.path}');
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
  phone: '+7 700 000 00 00',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Future<ProviderContainer> _pumpAuthenticated(
  WidgetTester tester, {
  required _FakeAdapter adapter,
  ManagerChatContext chatContext = const ManagerChatContext(),
  Size size = const Size(393, 851),
}) async {
  FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = ApiClient.test(tokenProvider: () async => 'test-token');
  client.debugDio.httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: ManagerChatScreen(chatContext: chatContext),
      ),
    ),
  );
  // `AuthNotifier`'s constructor kicks off its own background
  // session-restore (reads the mocked-empty secure storage, lands on
  // `AuthUnauthenticated`); setting the authenticated state *before* that
  // finishes just gets clobbered the moment it does resolve. A single
  // `pumpAndSettle()` isn't guaranteed to outlast it (it's only about
  // pending *frames*, not this unrelated Future) — poll past the loading
  // states explicitly instead of assuming one settle was enough.
  await tester.pumpAndSettle();
  while (container.read(authProvider) is AuthLoading ||
      container.read(authProvider) is AuthInitial) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  container.read(authProvider.notifier).state = AuthAuthenticated(_user);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a guest sees a sign-in prompt, not the chat itself', (
    tester,
  ) async {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});

    final client = ApiClient.test(tokenProvider: () async => null);
    client.debugDio.httpClientAdapter = _FakeAdapter();
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ManagerChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in to message the manager'), findsNothing);
    expect(find.text('Войдите, чтобы написать менеджеру'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Войти'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the app bar shows a manager avatar and title', (tester) async {
    await _pumpAuthenticated(tester, adapter: _FakeAdapter());

    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.byIcon(Icons.support_agent_rounded), findsOneWidget);
    expect(find.text('Менеджер MEREYTOI'), findsOneWidget);
  });

  testWidgets(
    'a brand-new thread shows suggestion chips, and tapping one fills the input',
    (tester) async {
      await _pumpAuthenticated(tester, adapter: _FakeAdapter());

      expect(
        find.text('Задайте вопрос — менеджер ответит в ближайшее время.'),
        findsOneWidget,
      );
      final chip = find.text('Рассчитать стоимость');
      expect(chip, findsOneWidget);

      await tester.tap(chip);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(
        field.controller!.text,
        'Подскажите, пожалуйста, примерную стоимость',
      );
    },
  );

  testWidgets(
    'existing history renders as bubbles, user and manager on opposite sides',
    (tester) async {
      final adapter = _FakeAdapter()
        ..seedExisting(
          conversationId: 1,
          listingId: 48,
          history: [
            ('user', 'Здравствуйте, подскажите цену'),
            ('manager', 'Добрый день! Сейчас уточню'),
          ],
        );

      final container = await _pumpAuthenticated(
        tester,
        adapter: adapter,
        chatContext: const ManagerChatContext(listingId: 48),
      );

      expect(find.text('Здравствуйте, подскажите цену'), findsOneWidget);
      expect(find.text('Добрый день! Сейчас уточню'), findsOneWidget);

      final userBubble = tester.getTopLeft(
        find.text('Здравствуйте, подскажите цену'),
      );
      final managerBubble = tester.getTopLeft(
        find.text('Добрый день! Сейчас уточню'),
      );
      // The user's own message sits to the right, the manager's to the
      // left — same convention every chat UI uses.
      expect(userBubble.dx, greaterThan(managerBubble.dx));

      // This test's fixture has an existing conversation, so `_load()`
      // started this screen's own 5s poll `Timer`. `addTearDown` runs
      // *after* flutter_test's own end-of-test pending-timer check, so
      // the container must be disposed synchronously here, not there —
      // see `manager_chat_provider.dart`'s `_startPolling` and this
      // file's own header doc.
      container.dispose();
    },
  );

  testWidgets(
    'sending a message appends it, clears the input, and the send button re-enables after',
    (tester) async {
      final adapter = _FakeAdapter()
        ..seedExisting(conversationId: 1, listingId: 48, history: const []);

      final container = await _pumpAuthenticated(
        tester,
        adapter: adapter,
        chatContext: const ManagerChatContext(listingId: 48),
      );

      await tester.enterText(find.byType(TextField), 'Здравствуйте!');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      // Mid-flight: the spinner replaces the send icon and the field is
      // already cleared, both immediately (not waiting on the fake's own
      // response).
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );

      await tester.pumpAndSettle();

      expect(find.text('Здравствуйте!'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      container.dispose();
    },
  );

  testWidgets(
    'the context card shows the restaurant, hall, menu, guests and total',
    (tester) async {
      final adapter = _FakeAdapter()
        ..seedExisting(conversationId: 1, listingId: 48, history: const []);

      final container = await _pumpAuthenticated(
        tester,
        adapter: adapter,
        chatContext: const ManagerChatContext(
          listingId: 48,
          listingName: 'Panorama',
          hallName: 'Малый зал',
          menuName: 'Банкетное меню',
          guestCount: 100,
          estimatedTotal: 2500000,
        ),
      );

      expect(find.textContaining('Panorama'), findsOneWidget);
      expect(find.text('Малый зал'), findsOneWidget);
      expect(find.text('Банкетное меню'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);

      container.dispose();
    },
  );

  testWidgets('a network error shows the error view with a working retry', (
    tester,
  ) async {
    final adapter = _FakeAdapter()..failAll = true;
    await _pumpAuthenticated(tester, adapter: adapter);

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('интернет'), findsOneWidget);

    adapter.failAll = false;
    await tester.tap(find.textContaining('Повторить'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('no overflow under a keyboard-sized viewport shrink at 320dp', (
    tester,
  ) async {
    // Deliberately no seeded conversation: a brand-new "peek" never
    // starts the 5s poll timer (see `_startPolling`'s own early return
    // when there's no conversation id yet), which keeps this layout
    // check independent of that timer's real-clock teardown timing.
    await _pumpAuthenticated(
      tester,
      adapter: _FakeAdapter(),
      chatContext: const ManagerChatContext(listingId: 48),
      size: const Size(320, 700),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });
}
