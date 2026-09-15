import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The site supports RU/KZ via a simple client-side toggle (see
/// frontend/src/context/AppProviders.jsx's `T`/`useLang`) rather than
/// full Flutter `intl` message catalogs — the API already returns both
/// `name_ru`/`name_kz` per record, so the app just needs to remember which
/// one the user wants and a tiny helper for the app's own static strings.
///
/// `en` exists as a third value (not yet reachable from the UI — no
/// toggle offers it) because the site itself has started adding English
/// copy for one flow (`<T ru kz en/>` in the event-request/booking area,
/// see frontend/src/context/AppProviders.jsx's own `T` component) — this
/// keeps the app's helper shape compatible with that without requiring
/// every one of today's `t()` call sites to supply an `en` string.
enum AppLocale { ru, kz, en }

final localeProvider = StateProvider<AppLocale>((ref) => AppLocale.ru);

/// Picks between hardcoded strings by locale — the Dart equivalent of the
/// site's `<T ru="..." kz="..." en="..."/>`. `en` is optional and falls
/// back to `ru`, mirroring `T`'s own `en ?? ru` behavior exactly — a call
/// site that never passes `en` keeps working unchanged even once
/// `AppLocale.en` becomes reachable.
String t(
  AppLocale locale, {
  required String ru,
  required String kz,
  String? en,
}) {
  switch (locale) {
    case AppLocale.kz:
      return kz;
    case AppLocale.en:
      return en ?? ru;
    case AppLocale.ru:
      return ru;
  }
}
