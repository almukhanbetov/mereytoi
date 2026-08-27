import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The site supports RU/KZ via a simple client-side toggle (see
/// frontend/src/context/AppProviders.jsx's `T`/`useLang`) rather than
/// full Flutter `intl` message catalogs — the API already returns both
/// `name_ru`/`name_kz` per record, so the app just needs to remember which
/// one the user wants and a tiny helper for the app's own static strings.
enum AppLocale { ru, kz }

final localeProvider = StateProvider<AppLocale>((ref) => AppLocale.ru);

/// Picks between two hardcoded strings by locale — the Dart equivalent of
/// the site's `<T ru="..." kz="..." />`.
String t(AppLocale locale, {required String ru, required String kz}) {
  return locale == AppLocale.kz ? kz : ru;
}
