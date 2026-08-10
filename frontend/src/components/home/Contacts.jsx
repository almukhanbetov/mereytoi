'use client';

import { useState } from 'react';
import Reveal from '@/components/Reveal';
import { T, useLang } from '@/context/AppProviders';
import { createBooking } from '@/lib/bookingApi';
import { AGENCY_PHONE_DISPLAY, AGENCY_WHATSAPP_DIGITS } from '@/lib/agencyContact';

const EVENT_TYPES = [
  { value: 'wedding', ru: 'Свадьба', kz: 'Үйлену тойы' },
  { value: 'anniversary', ru: 'Юбилей', kz: 'Мерейтой' },
  { value: 'corporate', ru: 'Корпоратив', kz: 'Корпоратив' },
  { value: 'other', ru: 'Другое', kz: 'Басқа' },
];

function buildAgencyWhatsAppText({ name, phone, typeLabel, message, lang }) {
  const lines = [
    lang === 'kz' ? '🔔 Сайттан жаңа өтінім — MEREYTOI' : '🔔 Новая заявка с сайта — MEREYTOI',
    '',
    `${lang === 'kz' ? 'Аты' : 'Имя'}: ${name}`,
    `Телефон: ${phone}`,
    `${lang === 'kz' ? 'Той түрі' : 'Тип торжества'}: ${typeLabel}`,
  ];
  if (message) {
    lines.push('', `${lang === 'kz' ? 'Хабарлама' : 'Сообщение'}:`, message);
  }
  return lines.join('\n');
}

export default function Contacts() {
  const { lang } = useLang();
  const [submitted, setSubmitted] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  async function handleSubmit(e) {
    e.preventDefault();
    setError('');
    setSubmitting(true);

    const form = e.target;
    // Opened synchronously (before the await below) so browsers don't treat
    // it as a blocked popup — a window.open() after an async gap loses the
    // "direct user gesture" that lets it bypass the popup blocker.
    const waWindow = window.open('', '_blank');

    const formData = new FormData(form);
    const name = formData.get('name')?.toString().trim() || '';
    const phone = formData.get('phone')?.toString().trim() || '';
    const message = formData.get('message')?.toString().trim() || '';
    const typeValue = formData.get('type')?.toString() || EVENT_TYPES[0].value;
    const typeObj = EVENT_TYPES.find((t) => t.value === typeValue) || EVENT_TYPES[0];
    const typeLabel = lang === 'kz' ? typeObj.kz : typeObj.ru;

    try {
      await createBooking({
        name,
        phone,
        message: `${lang === 'kz' ? 'Той түрі' : 'Тип торжества'}: ${typeLabel}${message ? `\n\n${message}` : ''}`,
        items: [],
      });

      const waText = buildAgencyWhatsAppText({ name, phone, typeLabel, message, lang });
      const waUrl = `https://wa.me/${AGENCY_WHATSAPP_DIGITS}?text=${encodeURIComponent(waText)}`;
      if (waWindow) waWindow.location.href = waUrl;
      else window.open(waUrl, '_blank', 'noopener,noreferrer');

      setSubmitted(true);
      form.reset();
      setTimeout(() => setSubmitted(false), 5000);
    } catch (err) {
      if (waWindow) waWindow.close();
      setError(err.message || (lang === 'kz' ? 'Жіберу сәтсіз аяқталды' : 'Не удалось отправить заявку'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="contacts" id="contacts">
      <div className="container contacts__inner">
        <Reveal className="contacts__info">
          <p className="section-eyebrow"><T ru="СВЯЖИТЕСЬ С НАМИ" kz="БАЙЛАНЫСҚА ШЫҒУ" /></p>
          <h2 className="section-title"><T ru="Спланируйте той уже сегодня" kz="Тойыңызды бүгін жоспарлаңыз" /></h2>
          <p className="section-desc"><T ru="Оставьте заявку — мы свяжемся с вами в течение 30 минут" kz="Өтінім қалдырыңыз — 30 минут ішінде хабарласамыз" /></p>

          <ul className="contacts__list">
            <li><span className="contacts__icon">📞</span><a href={`tel:+${AGENCY_WHATSAPP_DIGITS}`}>{AGENCY_PHONE_DISPLAY}</a></li>
            <li><span className="contacts__icon">✉️</span><a href="mailto:hello@mereytoi.kz">hello@mereytoi.kz</a></li>
            <li><span className="contacts__icon">📍</span><span><T ru="г. Алматы, пр. Достык, 100" kz="Алматы қ., Достық даңғылы, 100" /></span></li>
          </ul>

          <div className="contacts__social">
            <a href="#" aria-label="Instagram">IG</a>
            <a href="#" aria-label="WhatsApp">WA</a>
            <a href="#" aria-label="Telegram">TG</a>
          </div>
        </Reveal>

        <Reveal as="form" className="contacts__form" onSubmit={handleSubmit}>
          <div className="form-row">
            <label>
              <span><T ru="Ваше имя" kz="Атыңыз" /></span>
              <input type="text" name="name" required placeholder="Aidos" />
            </label>
            <label>
              <span><T ru="Телефон" kz="Телефон" /></span>
              <input type="tel" name="phone" required placeholder="+7 700 000 00 00" />
            </label>
          </div>
          <label>
            <span><T ru="Тип торжества" kz="Той түрі" /></span>
            <select name="type" defaultValue="wedding">
              {EVENT_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{lang === 'kz' ? t.kz : t.ru}</option>
              ))}
            </select>
          </label>
          <label>
            <span><T ru="Сообщение" kz="Хабарлама" /></span>
            <textarea name="message" rows="3" placeholder="..."></textarea>
          </label>
          {error && <p className="admin-login__error">{error}</p>}
          <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
            {submitting
              ? <T ru="Отправляем…" kz="Жіберілуде…" />
              : <T ru="Отправить заявку" kz="Өтінім жіберу" />}
          </button>
          <p className={`form-success${submitted ? ' is-visible' : ''}`}>
            <T ru="Спасибо! Мы скоро свяжемся с вами." kz="Рахмет! Жақын арада хабарласамыз." />
          </p>
        </Reveal>
      </div>
    </section>
  );
}
