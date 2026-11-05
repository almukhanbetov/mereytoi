# MEREYTOI — Development Rules

Этот файл содержит постоянные правила разработки MEREYTOI.  
Следовать им во всех задачах, если конкретный prompt явно не говорит иначе.

---

# 1. PROJECT CONTEXT

MEREYTOI — сервис организации мероприятий.

Основные части:

- Backend: Go + Gin + PostgreSQL
- Frontend: Next.js
- Mobile: Flutter
- Production: VPS
- Production URL: `https://mereytoi.kz`
- Android package: `kz.mereytoi.mereytoi_app`

Flutter должен использовать существующий backend API и работать с production API MEREYTOI.

Не создавать параллельную бизнес-логику в Flutter, если нужная логика уже существует в backend.

---

# 2. GENERAL DEVELOPMENT RULES

Перед изменением:

1. Найти существующую реализацию.
2. Понять текущий flow.
3. Переиспользовать существующую архитектуру.
4. Делать минимальное изменение, достаточное для задачи.

Запрещено без необходимости:

- переписывать работающие части;
- менять API contract;
- менять backend ради чисто UI-задачи;
- менять database schema ради UI-задачи;
- создавать дублирующие сервисы/providers/controllers;
- добавлять fake production data;
- добавлять временные заглушки, выдаваемые за готовый функционал;
- менять unrelated files.

Если найден существующий механизм — использовать его.

---

# 3. SCOPE CONTROL

Изменять только файлы, относящиеся к задаче.

Перед завершением всегда проверить:

```bash
git status
git diff
git diff --check
```

Если существуют незакоммиченные пользовательские изменения:

- не удалять;
- не перезаписывать;
- не включать случайно в commit;
- не stash/drop без необходимости;
- явно сообщить о конфликте, если он мешает задаче.

---

# 4. GIT POLICY

По умолчанию:

**НЕ выполнять:**

- commit
- push
- merge
- deploy
- release

без явной команды пользователя.

Рабочий порядок:

`implement → QA → report → commit → push → PR → review → merge → deploy`

Не push напрямую в `main`, если пользователь явно этого не попросил.

Перед commit:

```bash
git status
git diff --check
git diff --cached
```

В commit не должны попадать:

- `.env`
- passwords
- tokens
- API secrets
- keystores
- signing passwords
- SMTP passwords
- APK
- AAB
- build directories
- temporary QA files
- unrelated changes

---

# 5. SECURITY RULES

Никогда не выводить полностью:

- SMTP_PASSWORD
- JWT_SECRET
- DB_PASSWORD
- API secrets
- OAuth secrets
- Google App Password
- signing passwords
- production access tokens

Не показывать их:

- в терминальном отчёте;
- в Git diff;
- в logs;
- в commit;
- в PR;
- в documentation.

При необходимости проверки секретов показывать только:

`present / missing`

или masked значение.

Пример:

```text
SMTP_PASSWORD: PRESENT
```

а не само значение.

---

# 6. PRODUCTION SAFETY

Production URL:

```text
https://mereytoi.kz
```

Production нельзя изменять в процессе обычной разработки.

Без отдельного разрешения пользователя запрещено:

- менять реальные пользовательские данные;
- удалять production data;
- менять пароль реального пользователя;
- запускать destructive migration;
- включать feature flag;
- перезапускать production сервисы;
- выполнять deploy;
- отправлять реальные уведомления пользователям;
- выполнять тестовые платежи;
- создавать массовые записи.

Для read-only production проверки разрешено:

- health;
- container state;
- logs;
- schema inspection;
- безопасные SELECT;
- API GET;
- config status без раскрытия secrets.

---

# 7. DATABASE RULES

Перед изменением DB определить:

- нужна ли migration вообще;
- destructive ли изменение;
- совместимо ли оно со старыми данными;
- нужен ли backfill;
- можно ли сделать поле nullable/default.

Предпочитать backward-compatible изменения.

Никогда автоматически не:

- DROP TABLE;
- DROP COLUMN;
- массовый DELETE;
- TRUNCATE;
- irreversible migration.

Если задача затрагивает production schema — явно сообщить риск до deploy.

---

# 8. BACKEND RULES

Backend: Go/Gin/PostgreSQL.

После backend-изменений минимум:

```bash
go test ./...
go vet ./...
```

Для auth/security/database/concurrency изменений:

```bash
go test -race ./...
```

API должен:

- проверять auth;
- проверять ownership;
- не доверять client-supplied user/provider IDs;
- не раскрывать чужие данные;
- использовать корректные HTTP status codes;
- не раскрывать account existence в recovery/auth flows;
- валидировать input;
- не позволять изменять server-controlled fields.

---

# 9. FLUTTER RULES

Flutter должен сохранять функциональный паритет с web там, где это применимо.

Использовать существующий API.

Не создавать Flutter-only backend behavior.

После Flutter-изменений:

```bash
flutter analyze
flutter test
git diff --check
```

Для user-facing feature обязательно проверить:

- navigation;
- Back;
- loading;
- error;
- empty state;
- double tap;
- keyboard;
- scroll;
- overflow;
- touch targets;
- state refresh.

---

# 10. FLUTTER UX STANDARD

Общий стиль MEREYTOI:

- современный;
- лёгкий;
- premium;
- Kaspi-like simplicity без копирования Kaspi;
- light theme — default;
- тёплый белый / светлый фон;
- золотистый accent;
- мягкие тени;
- radius примерно 16–22;
- минимум визуального шума;
- без тяжёлых gradients;
- понятная hierarchy;
- большие touch targets.

Минимальный touch target:

```text
48dp
```

Не уменьшать readability ради декоративности.

---

# 11. RESPONSIVE QA

Для важных Flutter screens проверять:

```text
320dp
390dp
430dp
```

И реальное Android-устройство, если feature критичен.

Проверить:

- overflow = 0
- clipped text = 0
- unreachable CTA = 0
- keyboard overlap = 0
- broken scroll = 0

---

# 12. LANGUAGES

Flutter user-facing screens должны поддерживать:

- RU
- KZ
- EN

Не оставлять новые строки hardcoded только на одном языке.

Проверять:

- длину строк;
- button width;
- AppBar;
- dialogs;
- error messages;
- empty states.

Для админки допускается RU-only, если она уже проектно RU-only.

---

# 13. THEMES

Проверять:

- Light
- Dark

Не использовать hardcoded background/text colors, которые ломают другую тему.

---

# 14. AUTH RULES

Для login/logout/password recovery соблюдать:

- не раскрывать наличие аккаунта;
- rate limit;
- one-time tokens/codes;
- expiration;
- server-side validation;
- session revocation после password reset;
- безопасный logout;
- отсутствие token/password в logs.

Logout UX:

перед logout показывать подтверждение.

RU:

```text
Выйти из аккаунта?
Вы уверены, что хотите выйти?
Остаться
Выйти
```

`Stay / Back / outside` не должны завершать сессию.

Logout должен выполняться ровно один раз.

---

# 15. PASSWORD RECOVERY RULES

Поддерживаются несколько recovery paths:

- backup code;
- support-assisted recovery;
- email OTP, если feature включён.

Нельзя ломать существующий recovery flow при добавлении нового.

Email OTP:

- 6 digits;
- hash-only storage;
- TTL;
- one-time use;
- resend protection;
- rate limiting;
- neutral response для unknown email;
- code/password отсутствуют в logs.

`MAIL_ENABLED` и `PASSWORD_EMAIL_OTP_ENABLED` считать независимыми flags.

---

# 16. EMAIL / SMTP

SMTP credentials живут только в environment.

Никогда не commit SMTP credentials.

Для password recovery допускается:

```text
PASSWORD_EMAIL_OTP_ENABLED=true
MAIL_ENABLED=false
```

Это означает:

- password OTP работает;
- остальные email notifications выключены.

Перед включением real SMTP:

- проверить provider;
- TLS;
- sender;
- delivery;
- spam;
- rate limits.

---

# 17. PROVIDER MARKETPLACE RULES

Один пользователь может быть одновременно:

- клиентом;
- услугодателем.

Не создавать отдельный provider login.

Provider profile — расширение существующего user account.

Основные entry points:

- Home
- Profile

Если provider отсутствует:

```text
Стать услугодателем
```

Если provider существует:

```text
Мой бизнес
```

Не добавлять отдельный bottom-nav tab без отдельной продуктовой задачи.

---

# 18. PROVIDER PRIVACY

Provider может видеть client contact только по booking, который содержит услугу этого provider.

Нельзя показывать:

- чужие bookings;
- чужие provider items;
- чужие client contacts;
- foreign service subtotal.

Ownership должен проверяться server-side.

---

# 19. FAKE DATA POLICY

Не показывать fake production numbers.

Например statistics:

пока API нет:

```text
Статистика появится здесь
```

а не выдуманные просмотры/доходы/заявки.

---

# 20. GOOGLE MAPS

Не менять Maps API key/configuration, если задача не относится к картам.

Не повторять Maps signing QA после unrelated UI changes.

Maps release checks нужны при изменениях:

- Maps config;
- package;
- signing;
- manifest;
- API key;
- map implementation.

---

# 21. GOOGLE PLAY RELEASE

Перед Android release проверить:

- package;
- versionName;
- versionCode;
- release signing;
- debug signing not used;
- production API;
- no localhost;
- no temporary QA config;
- analyze;
- tests;
- AAB manifest.

Release artifact:

```text
flutter/build/app/outputs/bundle/release/app-release.aab
```

AAB не commit.

---

# 22. DEPLOYMENT

Merge в `main` может автоматически запустить GitHub Actions deploy.

Перед merge всегда учитывать этот факт.

После deploy выполнить PROD SMOKE.

Если GitHub Actions UI показывает странный статус, не делать автоматический rerun без проверки реального состояния:

- Docker images;
- running containers;
- commit/tag;
- `/api/health`;
- site HTTP status.

---

# 23. QA LEVELS

Использовать один из четырёх QA уровней.

---

## QA QUICK

Использовать для:

- text change;
- spacing;
- icon;
- small visual fix;
- isolated minor behavior.

Проверить:

```text
targeted test
flutter analyze if Flutter changed
git diff --check
relevant screen
```

Не запускать полный release QA без причины.

---

## QA FEATURE

Использовать для:

- нового screen;
- form;
- navigation;
- significant UI;
- business flow.

Проверить:

```text
flutter analyze
flutter test
git diff --check
RU/KZ/EN
light/dark
320/390/430
keyboard
scroll
Back
loading
error
empty state
double tap
overflow
```

Для критичного mobile flow:

```text
physical Android device
Flutter errors = 0
crash = 0
ANR = 0
relevant logcat errors = 0
```

---

## QA RELEASE

Перед release / major merge:

Backend:

```text
go test ./...
go vet ./...
go test -race ./...
```

Flutter:

```text
flutter analyze
flutter test
```

Общее:

```text
git diff --check
production config check
security check
device end-to-end
version
signing
AAB verification
```

---

## PROD SMOKE

После production deploy:

```text
deploy commit
container status
/api/health
site status
important APIs
DB migration status
5xx
panic
fatal
secrets in logs
```

Не выполнять destructive business transaction без отдельного разрешения.

---

# 24. SMART QA — НЕ ПОВТОРЯТЬ ЛИШНЕЕ

Не повторять unrelated QA.

Правило:

```text
Do not rerun previously-passed unrelated QA unless changed files can affect it.
```

Примеры:

Если изменился только текст кнопки:

не нужно заново проверять:

- signing;
- Google Maps SHA-1;
- backend race;
- production DB.

Если изменился auth backend:

нужно повторно проверить:

- auth tests;
- security;
- session behavior;
- recovery;
- race.

QA должен быть risk-based.

---

# 25. ERROR FIXING

Если QA находит bug:

1. определить root cause;
2. сделать минимальный fix;
3. повторить именно упавший сценарий;
4. затем соответствующий QA level.

Не переписывать feature целиком из-за одного локального дефекта.

---

# 26. DEVICE QA

Не использовать автоматические действия, которые могут мешать владельцу телефона.

Если телефон используется человеком:

- не выполнять агрессивные ADB действия без необходимости;
- учитывать incoming calls;
- не считать внешний системный overlay багом приложения;
- после QA вернуть временные phone settings.

---

# 27. BUILD ARTIFACTS

После QA/Release определить:

```text
APK/AAB created?
Is it current?
Version?
Signing?
Hash?
```

Но build artifacts никогда не commit.

---

# 28. FINAL REPORT STANDARD

После каждой задачи дать короткий структурированный отчёт.

Минимум:

```text
IMPLEMENTATION:
FILES CHANGED:
BACKEND CHANGED:
DB CHANGED:
FLUTTER ANALYZE:
FLUTTER TEST:
BACKEND TESTS:
GIT DIFF CHECK:
DEVICE QA:
KNOWN LIMITATIONS:
PRODUCTION TOUCHED:
READY TO COMMIT:
```

Показывать `N/A`, если пункт не относится к задаче.

Не скрывать:

- failed checks;
- skipped tests;
- unverified assumptions;
- production limitations.

---

# 29. COMMIT RULE

Commit только после успешного QA соответствующего уровня.

Commit message должен быть коротким и конкретным.

Примеры:

```text
feat: add provider onboarding flow
feat: add secure email OTP password recovery
fix: confirm before account logout
style: refine provider service cards
chore: bump Android version to 1.0.6+7
```

---

# 30. PROMPT INTERPRETATION

Если prompt пользователя короткий, например:

```text
MEREYTOI — добавить подтверждение выхода.
QA FEATURE.
Не commit/push/deploy.
```

нужно автоматически применить все правила этого `CLAUDE.md`.

Не требовать повторения стандартных QA/security/git требований.

---

# 31. PRIORITY

При конфликте правил использовать порядок:

1. Security
2. Data integrity
3. Explicit current user instruction
4. Existing architecture/API compatibility
5. Functional correctness
6. QA
7. UX consistency
8. Code cleanup

---

# 32. CORE PRINCIPLE

Главный принцип:

```text
Минимальное безопасное изменение → достаточный risk-based QA → отчёт → только затем Git/Deploy.
```

Не делать больше изменений, чем требуется задачей.
Не делать меньше проверок, чем требует риск задачи.
