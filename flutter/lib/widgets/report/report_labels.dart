import '../../state/locale_provider.dart';

// User-facing report texts, RU/KZ/EN.

String reportReasonLabel(AppLocale l, String code) => switch (code) {
  'spam' => t(l, ru: 'Спам', kz: 'Спам', en: 'Spam'),
  'fraud' => t(l, ru: 'Мошенничество', kz: 'Алаяқтық', en: 'Fraud'),
  'abuse' => t(l, ru: 'Оскорбления', kz: 'Қорлау', en: 'Abuse or insults'),
  'inappropriate' => t(
    l,
    ru: 'Неприемлемый контент',
    kz: 'Орынсыз мазмұн',
    en: 'Inappropriate content',
  ),
  'rights' => t(
    l,
    ru: 'Нарушение прав',
    kz: 'Құқықты бұзу',
    en: 'Rights violation',
  ),
  _ => t(l, ru: 'Другое', kz: 'Басқа', en: 'Other'),
};

const reportReasonCodes = [
  'spam',
  'fraud',
  'abuse',
  'inappropriate',
  'rights',
  'other',
];

/// The reporter's view of a status — no moderation details.
String reportStatusLabel(AppLocale l, String code) => switch (code) {
  'new' => t(l, ru: 'Отправлена', kz: 'Жіберілді', en: 'Sent'),
  'in_review' => t(
    l,
    ru: 'На рассмотрении',
    kz: 'Қаралуда',
    en: 'Under review',
  ),
  'resolved' => t(l, ru: 'Рассмотрена', kz: 'Қаралды', en: 'Reviewed'),
  'rejected' => t(l, ru: 'Отклонена', kz: 'Қабылданбады', en: 'Declined'),
  _ => code,
};

String reportTargetLabel(AppLocale l, String code) => switch (code) {
  'listing' => t(
    l,
    ru: 'Карточка услуги',
    kz: 'Қызмет карточкасы',
    en: 'Listing',
  ),
  'provider' => t(
    l,
    ru: 'Услугодатель',
    kz: 'Қызмет көрсетуші',
    en: 'Provider',
  ),
  'comment' => t(l, ru: 'Отзыв', kz: 'Пікір', en: 'Review'),
  _ => t(l, ru: 'Пользователь', kz: 'Пайдаланушы', en: 'User'),
};

/// A server refusal of a report, in words.
String? reportErrorText(AppLocale l, String? code) => switch (code) {
  'duplicate_report' => t(
    l,
    ru:
        'Вы уже пожаловались на это. Жалоба ещё рассматривается — повторно '
        'отправлять не нужно.',
    kz:
        'Сіз бұған шағымданып қойдыңыз. Шағым әлі қаралуда — қайта жіберудің '
        'қажеті жоқ.',
    en:
        "You've already reported this. It's still under review — no need to "
        'send it again.',
  ),
  'too_many_reports' => t(
    l,
    ru: 'Слишком много жалоб за короткое время. Попробуйте позже.',
    kz: 'Қысқа уақытта шағымдар тым көп. Кейінірек қайталаңыз.',
    en: 'Too many reports in a short time. Please try later.',
  ),
  'cannot_report_self' => t(
    l,
    ru: 'Нельзя пожаловаться на себя или свою карточку.',
    kz: 'Өзіңізге немесе өз карточкаңызға шағымдануға болмайды.',
    en: "You can't report yourself or your own listing.",
  ),
  'target_not_found' => t(
    l,
    ru: 'Это уже недоступно — возможно, удалено или скрыто.',
    kz: 'Бұл енді қолжетімсіз — жойылған немесе жасырылған болуы мүмкін.',
    en: 'This is no longer available — it may have been removed or hidden.',
  ),
  'details_required' => t(
    l,
    ru: 'Опишите проблему — не короче 5 символов.',
    kz: 'Мәселені сипаттаңыз — кемінде 5 таңба.',
    en: 'Describe the problem — at least 5 characters.',
  ),
  _ => null,
};
