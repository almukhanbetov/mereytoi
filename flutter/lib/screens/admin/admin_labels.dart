import 'package:intl/intl.dart';

import '../../core/network/api_exception.dart';

// Russian labels for the admin panel. The admin UI is Russian-only by
// agreement (like the web admin); user-facing screens stay RU/KZ/EN.

const reportReasonLabels = {
  'spam': 'Спам',
  'fraud': 'Мошенничество',
  'abuse': 'Оскорбления',
  'inappropriate': 'Неприемлемый контент',
  'rights': 'Нарушение прав',
  'other': 'Другое',
};

const reportStatusLabels = {
  'new': 'Новая',
  'in_review': 'В работе',
  'resolved': 'Решена',
  'rejected': 'Отклонена',
};

const reportTargetLabels = {
  'listing': 'Карточка',
  'provider': 'Услугодатель',
  'comment': 'Отзыв',
  'user': 'Пользователь',
};

const auditActionLabels = {
  'user.warn': 'Предупреждение',
  'user.block': 'Блокировка',
  'user.unblock': 'Разблокировка',
  'listing.hide': 'Скрытие карточки',
  'listing.restore': 'Восстановление карточки',
  'report.take': 'Жалоба взята в работу',
  'report.resolve': 'Жалоба решена',
  'report.reject': 'Жалоба отклонена',
};

const providerStatusLabels = {
  'active': 'Активен',
  'pending': 'На проверке',
  'draft': 'Черновик',
  'rejected': 'Отклонён',
  'suspended': 'Приостановлен',
};

const auditTargetLabels = {
  'user': 'Пользователь',
  'listing': 'Карточка',
  'report': 'Жалоба',
};

/// Block terms agreed for stage 1, in display order.
const blockDurations = <(String, String)>[
  ('1d', '1 день'),
  ('7d', '7 дней'),
  ('30d', '30 дней'),
  ('permanent', 'Бессрочно'),
];

String labelOf(Map<String, String> labels, String key) => labels[key] ?? key;

final _dateTime = DateFormat('dd.MM.yyyy HH:mm');

String formatAdminDate(DateTime? d) => d == null ? '—' : _dateTime.format(d);

/// A Russian message for an admin API failure, from the server's error code.
String adminErrorText(Object error) {
  if (error is ApiException) {
    switch (error.debugMessage) {
      case 'reason_required':
        return 'Укажите причину — не короче 3 символов.';
      case 'reason_too_long':
        return 'Причина слишком длинная (до 1000 символов).';
      case 'invalid_duration':
        return 'Выберите срок блокировки.';
      case 'cannot_target_self':
        return 'Нельзя применить это к своему аккаунту.';
      case 'cannot_block_admin':
        return 'Нельзя заблокировать администратора.';
      case 'not_blocked':
        return 'Пользователь уже разблокирован.';
      case 'already_hidden':
        return 'Карточка уже скрыта.';
      case 'not_hidden':
        return 'Карточка уже восстановлена.';
      case 'not_new':
        return 'Жалобу уже взял в работу другой администратор.';
      case 'already_decided':
        return 'По жалобе уже принято решение.';
      case 'target_changed':
        return 'Данные изменились. Обновите экран.';
      case 'admin access required':
        return 'Нет прав администратора.';
    }
    switch (error.type) {
      case ApiErrorType.network:
      case ApiErrorType.timeout:
        return 'Нет соединения с сервером. Проверьте интернет.';
      case ApiErrorType.notFound:
        return 'Не найдено — возможно, уже удалено.';
      case ApiErrorType.server:
        return 'Ошибка сервера. Попробуйте ещё раз.';
      default:
        break;
    }
  }
  return 'Не удалось выполнить действие. Попробуйте ещё раз.';
}
