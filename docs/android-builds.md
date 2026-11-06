# Android-сборки и Google Maps

Все сборки используют один Android-ключ Google Maps. Он различает приложения только по паре **package + SHA-1 подписи**, поэтому каждая пара из таблицы должна быть в ограничениях ключа.

## Схема сборок

| Сборка | Package | SHA-1 подписи | Чем подписана | Как получить |
|---|---|---|---|---|
| Основное приложение из Google Play | `kz.mereytoi.mereytoi_app` | `34:A6:FA:24:AD:00:08:B7:A6:2D:D9:4C:F6:AC:7A:97:87:04:8E:CB` | Ключ Play App Signing, хранится у Google | Загрузка AAB в Play |
| Локальная release-сборка | `kz.mereytoi.mereytoi_app` | `C2:81:AB:DB:1E:A9:81:FD:CC:CC:13:6E:F0:B1:F1:29:C8:BF:18:65` | Upload key | `flutter build apk --release` или `flutter build appbundle --release` |
| MEREYTOI TEST | `kz.mereytoi.mereytoi_app.qa` | `C2:81:AB:DB:1E:A9:81:FD:CC:CC:13:6E:F0:B1:F1:29:C8:BF:18:65` | Тот же upload key | `flutter/tool/build_test_apk.sh` |
| Локальная debug-сборка | `kz.mereytoi.mereytoi_app` | `52:97:6D:3B:D2:E7:A7:22:93:33:35:22:61:81:C1:75:4A:3B:69:68` | `~/.android/debug.keystore` этого компьютера | `flutter run` |

Ключ карт во всех сборках один и берётся из `MAPS_API_KEY` в `flutter/android/local.properties` (файл не в git) или из одноимённой переменной окружения. Release-сборка без него завершается ошибкой. Signing-данные лежат в `flutter/android/key.properties` (файл не в git).

SHA-1 — открытые отпечатки сертификатов, они не секретны. Значения ключа карт, паролей и keystore в документацию не записываются.

## Ограничения Android-ключа

В Google Cloud Console → APIs & Services → Credentials → Android-ключ → Application restrictions → Android apps должны быть все четыре пары из таблицы выше. Существующие записи не удаляются.

Новые записи нужны только при смене package, смене ключа подписи или сборке на другом компьютере в debug-режиме, потому что у него свой `debug.keystore`. Обычная пересборка, новая версия и новый `versionCode` настроек не требуют.

## MEREYTOI TEST

TEST ставится рядом с приложением из Play и его не заменяет. Обновить приложение из Play локальной сборкой нельзя: у них разные подписи (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Приложение из Play для этого не удаляют.

```bash
flutter/tool/build_test_apk.sh                 # настоящий сервер https://mereytoi.kz
flutter/tool/build_test_apk.sh --api URL       # локальный стенд для QA
adb install -r flutter/build/test-copy/mereytoi-test.apk
```

Package и название задаёт свойство Gradle `mereytoiTest` в `flutter/android/app/build.gradle.kts`. Без него сборка остаётся основным приложением. Скрипт завершается ошибкой, если получились не тот package или не та подпись.

Публикация из TEST на сервере `https://mereytoi.kz` сразу попадает в настоящий каталог. Для проверок с записью данных используйте `--api` с локальным стендом.

## Как проверить фактическую подпись

```bash
# Сборка из проекта
cd flutter/android && ./gradlew :app:signingReport

# APK: apksigner лежит в build-tools Android SDK
apksigner verify --print-certs app.apk

# APK из Play, снятый с телефона: Play добавляет подпись v3.2 для новых версий
# Android, которую apksigner может не разобрать, поэтому диапазон ограничивается
apksigner verify --print-certs --min-sdk-version 29 --max-sdk-version 34 base.apk
```

`keytool -printcert -jarfile` не читает APK с подписью только v2 и выше и ничего не выводит. Для отпечатка AAB он подходит, но это upload key, а не подпись приложения из Play.

Отказ ключа виден в журнале устройства:

```bash
adb logcat -d | grep -A3 "Authorization failure"
```

В сообщении указаны package и SHA-1, которые увидел Google. Значение ключа из этого журнала никуда не копируют.

## Две разные проверки карты

**Разрешение ключа.** Пройдена, если на устройстве нет `Authorization failure`, а карта показывает плитки. Это не доказывает точность координат.

**Точность выбора точки.** Проверяется отдельно после разрешения ключа, на локальном стенде:

1. Карта открывается в нужном месте: сохранённая точка или Алматы.
2. Нажатие возвращает координаты внутри видимой области, рядом с местом нажатия.
3. После сохранения и повторного открытия точка не смещается, значения совпадают.
4. При недоступной карте выбор отключён, а сохранённая точка не меняется.
