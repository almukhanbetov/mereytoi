'use client';

import { T } from '@/context/AppProviders';

// User-facing report texts, RU/KZ/EN.

export const REPORT_REASONS = ['spam', 'fraud', 'abuse', 'inappropriate', 'rights', 'other'];

export function ReasonLabel({ code }) {
  switch (code) {
    case 'spam': return <T ru="Спам" kz="Спам" en="Spam" />;
    case 'fraud': return <T ru="Мошенничество" kz="Алаяқтық" en="Fraud" />;
    case 'abuse': return <T ru="Оскорбления" kz="Қорлау" en="Abuse or insults" />;
    case 'inappropriate': return <T ru="Неприемлемый контент" kz="Орынсыз мазмұн" en="Inappropriate content" />;
    case 'rights': return <T ru="Нарушение прав" kz="Құқықты бұзу" en="Rights violation" />;
    default: return <T ru="Другое" kz="Басқа" en="Other" />;
  }
}

export function TargetLabel({ code }) {
  switch (code) {
    case 'listing': return <T ru="Карточка услуги" kz="Қызмет карточкасы" en="Listing" />;
    case 'provider': return <T ru="Услугодатель" kz="Қызмет көрсетуші" en="Provider" />;
    case 'comment': return <T ru="Отзыв" kz="Пікір" en="Review" />;
    default: return <T ru="Пользователь" kz="Пайдаланушы" en="User" />;
  }
}

// The reporter's view of a status — no moderation details.
export function StatusLabel({ code }) {
  switch (code) {
    case 'new': return <T ru="Отправлена" kz="Жіберілді" en="Sent" />;
    case 'in_review': return <T ru="На рассмотрении" kz="Қаралуда" en="Under review" />;
    case 'resolved': return <T ru="Рассмотрена" kz="Қаралды" en="Reviewed" />;
    case 'rejected': return <T ru="Отклонена" kz="Қабылданбады" en="Declined" />;
    default: return code;
  }
}

export function ReportError({ code }) {
  switch (code) {
    case 'duplicate_report':
      return <T ru="Вы уже пожаловались на это. Жалоба ещё рассматривается — повторно отправлять не нужно." kz="Сіз бұған шағымданып қойдыңыз. Шағым әлі қаралуда — қайта жіберудің қажеті жоқ." en="You've already reported this. It's still under review — no need to send it again." />;
    case 'too_many_reports':
      return <T ru="Слишком много жалоб за короткое время. Попробуйте позже." kz="Қысқа уақытта шағымдар тым көп. Кейінірек қайталаңыз." en="Too many reports in a short time. Please try later." />;
    case 'cannot_report_self':
      return <T ru="Нельзя пожаловаться на себя или свою карточку." kz="Өзіңізге немесе өз карточкаңызға шағымдануға болмайды." en="You can't report yourself or your own listing." />;
    case 'target_not_found':
      return <T ru="Это уже недоступно — возможно, удалено или скрыто." kz="Бұл енді қолжетімсіз — жойылған немесе жасырылған болуы мүмкін." en="This is no longer available — it may have been removed or hidden." />;
    case 'details_required':
      return <T ru="Опишите проблему — не короче 5 символов." kz="Мәселені сипаттаңыз — кемінде 5 таңба." en="Describe the problem — at least 5 characters." />;
    default:
      return <T ru="Не удалось отправить. Попробуйте ещё раз." kz="Жіберу мүмкін болмады. Қайталап көріңіз." en="Couldn't send it. Please try again." />;
  }
}
