# MEREYTOI — Этап 10А: Аудит Flutter APK на физическом Android

Дата: 2026-09-22
Автор проверки: Claude (аудит кода + автотесты + чтение production API), часть пунктов подтверждена пользователем на реальном устройстве (см. раздел 2).

**Методология.** Каждому пункту присвоен один статус:
- **PASS** — проверено (код + тест, или прямое подтверждение на устройстве) и работает.
- **FAIL** — дефект воспроизведён конкретно (код/API/тест), с доказательством.
- **BLOCKED** — проверку нельзя выполнить в текущей среде (нет интерактивного доступа к устройству у ассистента).
- **NOT TESTED** — не проверялось; отсутствие проверки **не считается** ошибкой.

У ассистента в этой сессии нет возможности самому тапать по экрану физического телефона (нет интерактивного драйвера UI) — `flutter run` на устройстве `4622f67a` запускает пользователь. Поэтому весь раздел 4, кроме пунктов, явно подтверждённых пользователем (раздел 2) или доказанных автотестом/API-вызовом, помечен NOT TESTED, а не PASS.

---

## 1. Git-состояние

```
pwd: /home/mukhtar/my-projects/MEREYTOI
branch: feature/event-request-flow (tracking origin/feature/event-request-flow, up to date)
```

Последние коммиты:
```
e2360ac feat: add restaurant ownership and manager access   ← уже задеплоен на production (см. Этап 10 report)
8fb1602 feat: complete Flutter mobile parity and UI
609f37e fix: make Google Place ID read-only
0933f0c fix: persist restaurant address from Google Places
a5779c1 feat: improve restaurant menus admin UI
7d59187 feat: improve restaurant halls admin UI
90e71c4 fix: pass Google Maps API key to frontend build
566a883 feat: add restaurant halls menus maps and workspace integration
```

Незакоммиченные изменения (все сохранены, ничего не удалено/не откачено): 21 файл Flutter — это UI управления рестораном (Profile → Мои рестораны → карточки/залы/меню/CRUD), построенный поверх ownership backend из `e2360ac`, но ещё не закоммиченный по явному указанию пользователя в предыдущих этапах. Полный список — `git status --short` в рабочей копии; ключевые:

- `lib/screens/profile/restaurant_admin/**` (новые) — список ресторанов владельца, экран управления, вкладки Основное/Залы/Меню/Адрес, форм-шиты hall/menu/section/item/extra.
- `lib/services/listing_management_service.dart`, `lib/state/listing_management_actions.dart` (новые) — CRUD-клиент к тем же admin/manage-эндпоинтам.
- `lib/screens/profile/profile_screen.dart`, `lib/models/listing.dart`, `lib/services/listing_service.dart`, `lib/state/listings_provider.dart`, `lib/state/providers.dart` (изменены) — подключение «Мои рестораны» через `GET /api/users/me/listings`.
- `test/services/listing_management_service_test.dart`, `test/state/listing_management_actions_test.dart` (новые тесты).

Ничего не закоммичено и не задеплоено в рамках этого этапа (по требованию задачи).

---

## 2. Подтверждено пользователем вручную на Android (принимается как факт, не перепроверялось)

| # | Пункт | Статус |
|---|---|---|
| 1 | Профиль загружает данные | PASS (подтверждено пользователем) |
| 2 | Отображаются залы и фотографии | PASS (подтверждено пользователем) |
| 3 | Услуги добавляются в корзину | PASS (подтверждено пользователем) |
| 4 | Открывается раздел «Мой той» | PASS (подтверждено пользователем) |
| 5 | Работает возврат назад на проверенных экранах | PASS (подтверждено пользователем) |

Остальное ниже — либо доказано кодом/тестом/API отдельно, либо NOT TESTED.

---

## 3. Окружение Android

```
flutter --version → Flutter 3.44.0 • channel stable • Dart 3.12.0 • DevTools 2.57.0
```

`flutter doctor -v`:
- Flutter: ✓
- Android toolchain: ✓ (Android SDK 36.1.0, build-tools 36.1.0, Java 21 из Android Studio, все лицензии приняты)
- Chrome (web): ✓
- Linux desktop toolchain: ✗ (нет clang/cmake/ninja/GTK3 — **не влияет на Android**, это только для `flutter run -d linux`)
- Connected device (3 available):
  - **`M2102J20SG` (mobile) • `4622f67a` • android-arm64 • Android 12 (API 31)** — физическое устройство подключено по USB, реально доступно.
  - Linux (desktop), Chrome (web) — не относятся к задаче.
- Network resources: ✓

`adb devices -l`: один физический девайс, `4622f67a`, `usb:4-1.8`, `product:vayu_global model:M2102J20SG`.

**Вывод**: физическое Android-устройство реально подключено и доступно — утверждение «протестировано на телефоне» правомерно только для пунктов раздела 2, подтверждённых пользователем лично; остальное я сам интерактивно не гонял (нет такого инструмента в этой среде).

### Конфигурация приложения

| Параметр | Значение | Источник |
|---|---|---|
| Package name (applicationId) | `kz.mereytoi.mereytoi_app` | `android/app/build.gradle.kts:19` |
| Namespace | `kz.mereytoi.mereytoi_app` | `android/app/build.gradle.kts:8` |
| App label | `MEREYTOI` | `AndroidManifest.xml:7` |
| Версия | `1.0.0+1` | `pubspec.yaml:19` |
| min/target/compile SDK | управляются Flutter tool (`flutter.minSdkVersion` и т.д.), **не захардкожены** в проекте | `android/app/build.gradle.kts:9,22,23` |
| Android permissions | только `android.permission.INTERNET` | `AndroidManifest.xml:4` — намеренно, приложение не использует камеру/геолокацию/хранилище |
| API base URL (debug и release одинаково) | `https://mereytoi.kz` по умолчанию, переопределяется только явным `--dart-define=API_BASE_URL=...` | `lib/core/config/api_config.dart:18-21` |

**Важно**: подтверждено чтением кода — приложение **не** указывает на `localhost` ни в debug, ни в release. Значение `API_BASE_URL` жёстко задано как `https://mereytoi.kz` через `String.fromEnvironment` с этим `defaultValue`; localhost возможен только если кто-то явно передаст `--dart-define` при сборке/запуске (никто в этой сессии этого не делал). Всё, что мы наблюдаем на телефоне сейчас — это реальный production API.

### Существующие APK

```
build/app/outputs/flutter-apk/app-debug.apk    196 858 814 байт   собран 2026-09-22 15:00
build/app/outputs/flutter-apk/app-release.apk   63 375 913 байт   собран 2026-09-22 14:04
```
(и зеркальные копии в `build/app/outputs/apk/{debug,release}/`). Оба собраны сегодня, актуальны.

---

## 4. Проверка авторизации, API, ресторанов/залов/меню, корзины, checkout/PDF, совместной работы, Android UI

Обозначения: код+тест = проверено статически и юнит/widget-тестом; API = проверено прямым HTTP-запросом к production (read-only, без изменения данных); устройство = требует живого взаимодействия с телефоном.

### 4.1 Авторизация и сессия

| Пункт | Статус | Доказательство |
|---|---|---|
| Хранение токена | PASS (код+тест) | `flutter_secure_storage`, `test/state/auth_provider_test.dart` (login/logout/claim — все проходят) |
| Восстановление сессии при старте | PASS (код+тест) | `AuthNotifier._restoreSession()` (`lib/state/auth_provider.dart:67-81`): нет токена → guest; есть токен → `GET /api/auth/me`; невалиден → тихий откат к guest. Покрыто тестами. |
| Выход из аккаунта | PASS (код+тест) | `logout()` чистит secure storage, тест зелёный |
| Обработка HTTP 401 | PASS (код) | Единый interceptor `ApiClient` → `_handleUnauthorized()` (`lib/state/auth_provider.dart:179-184`) чистит токен и переводит в `AuthUnauthenticated`; классификация 401→`ApiErrorType.unauthorized` в `lib/core/network/api_client.dart:167-176` |
| Обработка HTTP 403 | PASS (код) | Отдельный `ApiErrorType.forbidden`, показывает «Недостаточно прав», не сырую ошибку (`lib/core/utils/error_messages.dart:30-35`) |
| Обработка сетевых ошибок/таймаутов | PASS (код) | `DioExceptionType.connectionError`/`*Timeout` → отдельные типы с понятным текстом (`api_client.dart:132-138`) |
| Регистрация / авторизация на реальном устройстве | NOT TESTED | Не входит в подтверждённый список раздела 2; интерактивно не проверялось |

### 4.2 Рестораны, залы, меню — включая Panorama (listing_id=48)

Полный сценарий Список → карточка → залы → фото → меню → позиции **на устройстве** не проверялся (кроме пункта 2 «отображаются залы и фотографии», подтверждённого пользователем в общем виде). Ниже — то, что доказано отдельно кодом и прямым API-запросом к production (read-only, ничего не менялось).

**Production данные для Panorama проверены напрямую** (`GET https://mereytoi.kz/api/listings/48`, `/halls`, `/menus`, все `200`):

```
listing 48: name_ru=Panorama, is_active=true
halls:  1 — "QA Тестовый зал", capacity=100, is_active=true
menus:  1 — "QA Тестовое банкетное меню", price_per_guest=25000,
            hall_id=1, min_guests=50, max_guests=120, is_active=true
  sections: 1 — "QA Холодные закуски" → 1 item ("QA Мясное ассорти", 250 г)
  extras:   1 — "QA Детский стол", type=kids_table, price=12000, unit=per_guest
```

Данные реально существуют в БД, отдаются и через нестed `/listings/:id`, и через отдельные `/halls`/`/menus` (последние — именно то, что читает `RestaurantDetailScreen` через `listingHallsProvider`/`listingMenusProvider`, `lib/state/listings_provider.dart:28-40`). Значит для Panorama сейчас нет ни отсутствия данных в БД, ни ошибки API — оба уже исключены.

Owner listing 48 назначен (Этап 10): `user_id=3` (Arslan, role=user), подтверждено `GET /api/listings/48/managers` → одна запись, `role=owner`.

| Пункт | Статус | Доказательство |
|---|---|---|
| Парсинг JSON halls/menus/sections/items/extras | PASS (код+тест) | `ListingHall/ListingMenu/...fromJson` + `test/models/model_parsing_test.dart` и смежные — все существующие поля покрыты |
| Пустое состояние (0 залов/меню) не роняет экран | PASS (widget-тест) | `test/widgets/restaurant_empty_menus_test.dart` — прогоняет ровно этот сценарий против реальной формы production-ответа, зелёный |
| Публичный `RestaurantDetailScreen` реально показывает выбор зала/меню/гостей/калькулятор/«Добавить в корзину» для Panorama **на экране телефона** | NOT TESTED | Данные теперь есть (см. выше), код для этого написан и покрыт тестами на пустом состоянии — но живой прогон именно с данными на устройстве не выполнялся в этой сессии |
| Обновление после CRUD без перезапуска (owner добавил зал → публичный экран видит) | PASS (код+тест) | `test/state/listing_management_actions_test.dart` — `createHall`/`createMenu` инвалидируют `listingHallsProvider`/`listingMenusProvider`/`listingAllHallsProvider` |
| CRUD залов/меню на устройстве под owner-аккаунтом | NOT TESTED | Пользователь сам проверит (см. открытую задачу из предыдущего этапа) |

### 4.3 Калькулятор и корзина

| Пункт | Статус | Доказательство |
|---|---|---|
| Формула калькулятора (`price_per_guest × guests` + flat/per_guest/percent extras, именно в этом порядке) | PASS (код) | `lib/domain/restaurant/restaurant_price_calculator.dart:46-115` — точный порт формулы `RestaurantMenuCalculator.jsx`, включая то, что percent считается **после** сложения flat-экстр (порядок имеет значение) |
| Повторное добавление той же позиции → двойное начисление? | PASS, дефекта нет (код+тест) | `CartNotifier.addItem` (`lib/state/cart_provider.dart:54-57`) — **заменяет** элемент по `key=(listingId,hallId,menuId)`, а не добавляет второй. Покрыто `test/state/cart_provider_test.dart` («adding an already-present listingId replaces it rather than duplicating»). Двойного начисления нет. |
| «Изменение количества» в корзине | **NOT A BUG — by design** | В корзине **нет** отдельного контрола «изменить количество/гостей» — это осознанное решение (комментарий `cart_provider.dart:7-15`: «no generic quantity field», зеркалит web). Изменить состав можно только вернувшись на экран ресторана/услуги и повторно нажав «Добавить в корзину» — сработает как replace. `cart_screen.dart` показывает `guests × unitPrice` только для чтения (строки 246-257, 291-318) и даёт только «Удалить» (строка 272). Если ожидался именно in-cart степпер — это отсутствующая фича, не баг существующей. |
| Удаление позиции | PASS (код+тест) | `removeItem` фильтрует по `key`, тест `cart_provider_test.dart` зелёный |
| Пересчёт общей суммы | PASS (код+тест) | `cartTotalProvider` суммирует `totalPrice` по всем items (`cart_provider.dart:95-99`), тест `cartTotalProvider sums totalPrice across all items` зелёный |
| Сохранение состояния корзины между экранами/перезапуском | PASS (код+тест) | `CartStorage` (shared_preferences), восстановление в конструкторе `CartNotifier`, тест `shared_preferences persistence` зелёный |
| Нулевое/минимальное количество гостей, отсутствие цены | PASS (код) | `checkout_validation.dart:21-36` — блокирует checkout при `guests<=0` или отсутствующем `estimatedTotal`; `isGuestCountWithinBounds` (строки 44-49) проверяет `min_guests`/`max_guests` |
| Живое поведение калькулятора/корзины на экране | NOT TESTED | Требует устройства |

Новых правил ценообразования не вводилось — весь расчёт зеркалит уже существующую формулу web/backend.

### 4.4 Оформление заявки и PDF

| Пункт | Статус | Доказательство |
|---|---|---|
| Обязательные поля (имя, телефон) | PASS (код) | `TextFormField` с непустым `validator` для обоих полей (`checkout_screen.dart:157-174`) |
| Валидация корзины перед checkout | PASS (код) | `validateCartForCheckout` — пустая корзина / нет `estimated_total` / некорректные guests (`checkout_validation.dart:21-36`) |
| PDF не дублирует backend | PASS (код, перепроверено) | Backend не генерирует PDF — подтверждено `grep -rn "pdf" backend/internal/routes backend/internal/handlers` = пусто (перепроверено в этой сессии). Единственная реализация — `lib/services/pdf_service.dart`, что и задокументировано в его собственном комментарии. |
| Наличие телефона в PDF | PASS (код) | `pdf_service.dart:52-62` — строка `customerName · customerPhone` печатается, если хоть одно поле не пусто |
| Формирование/открытие PDF на устройстве | NOT TESTED | Требует устройства |
| Реальное бронирование в production | Не создавалось (по требованию задачи) | — |

### 4.5 Совместная работа — «Мой той» vs restaurant ownership

Две **разные, не смешанные** модели прав в системе (проверено чтением backend и Flutter кода в этой и предыдущих сессиях):

- **`listing_managers`** (`backend/internal/models/listing_manager.go`) — owner/manager конкретного ресторана/локации (`Listing`). Доступ проверяет `RequireListingAccess` (admin bypass либо совпадение `listing_id`+`user_id` из JWT). Никак не пересекается с событиями.
- **`EventMember`** (`backend/internal/models/event.go`) — участник конкретного «Той» (`Event`), роли `viewer/editor/owner`, отдельный `RequireEventRole`. Приглашения — `EventInvitation`.

Flutter это разделение не путает — нет ни одного места, где `ListingManager`-роль подставляется вместо `EventMember`-роли или наоборот.

| Пункт | Статус | Доказательство |
|---|---|---|
| Экран «Мой той» открывается | PASS (подтверждено пользователем) | Раздел 2 |
| Владелец события может создать приглашение | PASS (код) | `EventService.createInvitation`/`listInvitations`/`revokeInvitation` (`lib/services/event_service.dart:311-341`), UI в `lib/widgets/events/members_tab.dart` |
| **Открытие ссылки-приглашения приглашённым** | **FAIL — подтверждённый дефект, см. раздел 5, пункт D-1** | Веб генерирует `https://mereytoi.kz/invite/:token`, но у Android-приложения нет intent-filter на `/invite` (только на `/claim` — `AndroidManifest.xml:34-48`), и `DeepLinkService` умеет парсить только claim-токен (`deep_link_service.dart:40-42`). `EventService.previewInvitation`/`acceptInvitation` (строки 404-409) реализованы, но **ни один экран/провайдер их не вызывает** — мёртвый код. |
| Доступ к данным события ограничен ролью | PASS (backend, проверено ранее) | `RequireEventRole` + существующие backend-тесты (`TestViewerCannotEditButCanVote`, `TestOutsiderCannotAccessEventByGuessingID` и др.) |
| Чат (manager chat) | NOT TESTED | Не входит в список раздела 2 |
| Уведомления | NOT TESTED | Не входит в список раздела 2 |

Мобильная админка не добавлялась, доступ пользователей ради тестов не расширялся — оба требования соблюдены.

### 4.6 Android UI

Реальную интерактивную проверку (системная Back, клавиатура, скролл форм, сворачивание/возврат) я в этой сессии не выполнял — нет инструмента для управления физическим экраном. Что подтверждено иначе:

| Пункт | Статус | Доказательство |
|---|---|---|
| Системная кнопка Back на проверенных экранах | PASS (подтверждено пользователем) | Раздел 2, пункт 5 |
| Кастомная обработка Back вне стандартного Navigator pop | Есть только в одном месте | `grep -rl "PopScope\|WillPopScope" lib/` → только `lib/screens/checkout/booking_success_screen.dart`. Везде больше — стандартное поведение Navigator. |
| Overflow на разных ширинах экрана | PASS (widget-тест, не устройство) | `test/widgets/overflow_test.dart` — рендерит `CategoryFilterBar`+picker на 360×800, 390×844, 412×915, 430×932, без overflow, зелёный |
| `windowSoftInputMode` для клавиатуры | Настроено | `AndroidManifest.xml:16` — `adjustResize` |
| Пустые состояния / индикаторы загрузки / сетевые ошибки | PASS (код, широко) | `AppErrorView` — 21 использование, `AppSkeleton` — 9, `RefreshIndicator` — 11 мест в `lib/` |
| Глобальный перехват необработанных ошибок (защита от неожиданного закрытия) | **Отсутствует — риск, не подтверждённый крэш** | `lib/main.dart` — голый `runApp`, нет `runZonedGuarded`/`FlutterError.onError`/`PlatformDispatcher.instance.onError`. Я не наблюдал реального крэша — это архитектурный риск, а не воспроизведённый дефект. См. раздел 7. |
| Клавиатура, скролл форм, сворачивание/возврат приложения | NOT TESTED | Требует устройства |

---

## 5. Таблица подтверждённых дефектов

| ID | Экран/область | Шаги воспроизведения | Ожидаемый результат | Фактический результат | Причина (подтверждена) | Файл:строка |
|---|---|---|---|---|---|---|
| D-1 | Приём приглашения в «Мой той» | Владелец события создаёт приглашение → делится ссылкой `https://mereytoi.kz/invite/<token>` → приглашённый открывает ссылку на Android с установленным приложением MEREYTOI | Приложение перехватывает ссылку (App Link) и открывает экран предпросмотра/принятия приглашения | Intent-filter под `/invite` отсутствует — ссылка уходит в браузер/диспетчер без предложения открыть приложение; даже если бы токен попал в приложение вручную, нет экрана, вызывающего `previewInvitation`/`acceptInvitation` | Подтверждено кодом: `AndroidManifest.xml` регистрирует только `pathPrefix="/claim"` (строки 34-48); `DeepLinkService._handle` парсит только claim-токен (`deep_link_service.dart:40-42`); `EventService.previewInvitation`/`acceptInvitation` (`event_service.dart:404,409`) не имеют ни одного вызывающего места в `lib/screens`, `lib/state` | `flutter/android/app/src/main/AndroidManifest.xml:34-48`, `flutter/lib/core/deeplink/deep_link_service.dart:40-48`, `flutter/lib/services/event_service.dart:404-409` |

Других воспроизведённых дефектов в этом этапе не найдено. Всё, что могло бы выглядеть как дефект при поверхностном взгляде, разобрано отдельно и оказалось либо сознательным решением («изменение количества» в корзине — см. 4.3), либо неприменимо (PDF-дублирование, локальный API).

---

## 6. Функции, которые ещё не удалось проверить (NOT TESTED / BLOCKED)

Причина одна и та же для всех: нет инструмента для интерактивного управления физическим экраном в этой среде — устройство подключено и доступно, но провести тап/скролл/ввод текста может только пользователь через `flutter run -d 4622f67a`.

- Регистрация / авторизация нового пользователя на экране.
- Полный сценарий Panorama: выбор зала → выбор меню → степпер гостей → доп.услуги → калькулятор → «Добавить в корзину» (данные для этого теперь реально существуют в production, см. 4.2).
- CRUD залов/меню/секций/позиций/доп.услуг под owner-аккаунтом (Arslan) прямо на устройстве.
- Изменение количества гостей у уже добавленной в корзину позиции через реальный UI-поток (повторное открытие экрана ресторана).
- Оформление заявки целиком (создание заявки → успех → PDF → открытие/шаринг PDF, включая корректность телефона в готовом файле).
- Manager chat (открытие, отправка сообщения, уведомления о новом сообщении).
- Уведомления (список, пометка прочитанным, переход по уведомлению).
- Открытие ссылки-приглашения на «Мой той» (частично — уже FAIL, см. D-1; но полный live-повтор на устройстве не проводился).
- Клавиатура поверх форм, скролл длинных форм, поведение при сворачивании/восстановлении приложения.
- Поведение при потере сети посреди действия (а не просто типа ошибки в коде).

---

## 7. Приоритеты исправлений

1. **P1 — D-1, приём приглашений «Мой той».** Единственный подтверждённый функциональный дефект. Блокирует основной сценарий совместной работы для приглашённого участника на мобильном — сейчас туда физически нельзя попасть. Нужно: (а) добавить `intent-filter` под `pathPrefix="/invite"` в `AndroidManifest.xml` (и `apple-app-site-association`/entitlements для iOS, если он есть в скоупе), (б) научить `DeepLinkService`/`claim_deep_link.dart`-аналог распознавать `/invite/:token`, (в) добавить экран предпросмотра/принятия приглашения, использующий уже готовые `previewInvitation`/`acceptInvitation`.
2. **P2 — глобальный перехват ошибок.** Не дефект, а риск: добавить `runZonedGuarded` + `FlutterError.onError` в `main.dart`, чтобы неожиданный exception логировался, а не (потенциально) ронял процесс без следа. Дешёвое, безопасное защитное изменение.
3. **P3 — живая проверка на устройстве** всего, что помечено NOT TESTED в разделе 6, в первую очередь полного сценария Panorama (данные уже готовы) и CRUD под owner-аккаунтом — это то, ради чего был поднят весь ownership-стек в Этапах 1–10.
4. Ничего в этом отчёте не указывает на проблемы с корзиной/калькулятором/PDF/авторизацией — они разобраны и либо PASS, либо явно NOT TESTED без признаков поломки.

---

## 8. План этапа 10Б

1. Пользователь проходит на телефоне полный сценарий Panorama (раздел 6, пункты 2-3) под owner-аккаунтом Arslan — это закрывает последнюю непроверенную часть Этапов 1–10.
2. По результатам — либо фиксируем PASS по всей цепочке зал→меню→калькулятор→корзина, либо получаем новый воспроизводимый дефект с логами устройства.
3. Параллельно/после — чиню D-1 (deep link для `/invite`) минимальным изменением: манифест + парсер токена + один новый экран, переиспользующий уже существующие `previewInvitation`/`acceptInvitation`.
4. Добавляю `runZonedGuarded`/`FlutterError.onError` в `main.dart` (P2) — небольшое, самостоятельное изменение, не трогающее бизнес-логику.
5. Прогоняю оставшиеся пункты раздела 6 (чат, уведомления, checkout+PDF целиком, клавиатура/скролл/сворачивание) на устройстве вместе с пользователем и фиксирую реальные PASS/FAIL вместо NOT TESTED.

Ничего из этого не требует немедленного отдельного согласования — все пункты укладываются в уже одобренные рамки (не менять бизнес-логику/цены, не трогать backend без нужды, не коммитить/не деплоить без отдельной команды). Конкретные commit/deploy — по-прежнему только по явному запросу.
