import '../../state/locale_provider.dart';
import '../network/api_exception.dart';

/// Turns an [ApiErrorType] into the same kind of short, friendly line the
/// site shows on its own forms (e.g. "Не удалось отправить заявку.
/// Попробуйте ещё раз.") — never a raw exception message.
String apiErrorMessage(AppLocale locale, Object error) {
  if (error is ApiException) {
    switch (error.type) {
      case ApiErrorType.network:
        return t(locale, ru: 'Нет подключения к интернету', kz: 'Интернет байланысы жоқ');
      case ApiErrorType.timeout:
        return t(locale, ru: 'Сервер не отвечает. Попробуйте ещё раз', kz: 'Сервер жауап бермей тұр. Қайта көріңіз');
      case ApiErrorType.notFound:
        return t(locale, ru: 'Ничего не найдено', kz: 'Ештеңе табылмады');
      case ApiErrorType.server:
        return t(locale, ru: 'Сервис временно недоступен', kz: 'Қызмет уақытша қолжетімсіз');
      case ApiErrorType.unknown:
        return t(locale, ru: 'Не удалось загрузить данные', kz: 'Деректерді жүктеу мүмкін болмады');
    }
  }
  return t(locale, ru: 'Не удалось загрузить данные', kz: 'Деректерді жүктеу мүмкін болмады');
}
