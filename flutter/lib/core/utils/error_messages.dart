import '../../state/locale_provider.dart';
import '../network/api_exception.dart';

/// Turns an [ApiErrorType] into the same kind of short, friendly line the
/// site shows on its own forms (e.g. "Не удалось отправить заявку.
/// Попробуйте ещё раз.") — never a raw exception message.
String apiErrorMessage(AppLocale locale, Object error) {
  if (error is ApiException) {
    switch (error.type) {
      case ApiErrorType.network:
        return t(
          locale,
          ru: 'Нет подключения к интернету',
          kz: 'Интернет байланысы жоқ',
          en: 'No internet connection',
        );
      case ApiErrorType.timeout:
        return t(
          locale,
          ru: 'Сервер не отвечает. Попробуйте ещё раз',
          kz: 'Сервер жауап бермей тұр. Қайта көріңіз',
          en: 'The server isn\'t responding. Try again',
        );
      case ApiErrorType.notFound:
        return t(
          locale,
          ru: 'Ничего не найдено',
          kz: 'Ештеңе табылмады',
          en: 'Nothing found',
        );
      case ApiErrorType.unauthorized:
        return t(
          locale,
          ru: 'Неверный email/телефон или пароль',
          kz: 'Email/телефон немесе құпия сөз қате',
          en: 'Incorrect email/phone or password',
        );
      case ApiErrorType.forbidden:
        return t(
          locale,
          ru: 'Недостаточно прав для этого действия',
          kz: 'Бұл әрекет үшін құқық жеткіліксіз',
          en: 'You don\'t have permission for this action',
        );
      case ApiErrorType.gone:
        return t(
          locale,
          ru: 'Ссылка больше не активна',
          kz: 'Сілтеме енді белсенді емес',
          en: 'This link is no longer active',
        );
      case ApiErrorType.conflict:
        return t(
          locale,
          ru: 'Этот email уже зарегистрирован',
          kz: 'Бұл email тіркелген',
          en: 'This email is already registered',
        );
      case ApiErrorType.server:
        return t(
          locale,
          ru: 'Сервис временно недоступен',
          kz: 'Қызмет уақытша қолжетімсіз',
          en: 'Service temporarily unavailable',
        );
      case ApiErrorType.unknown:
        return t(
          locale,
          ru: 'Не удалось загрузить данные',
          kz: 'Деректерді жүктеу мүмкін болмады',
          en: 'Couldn\'t load data',
        );
    }
  }
  return t(
    locale,
    ru: 'Не удалось загрузить данные',
    kz: 'Деректерді жүктеу мүмкін болмады',
    en: 'Couldn\'t load data',
  );
}
