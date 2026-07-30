'use client';

import { useState } from 'react';
import Reveal from '@/components/Reveal';
import { T, useLang } from '@/context/AppProviders';

const EVENT_TYPES = [
  { value: 'wedding', ru: 'Свадьба', kz: 'Үйлену тойы' },
  { value: 'anniversary', ru: 'Юбилей', kz: 'Мерейтой' },
  { value: 'corporate', ru: 'Корпоратив', kz: 'Корпоратив' },
  { value: 'other', ru: 'Другое', kz: 'Басқа' },
];

export default function Contacts() {
  const { lang } = useLang();
  const [submitted, setSubmitted] = useState(false);

  function handleSubmit(e) {
    e.preventDefault();
    setSubmitted(true);
    e.target.reset();
    setTimeout(() => setSubmitted(false), 5000);
  }

  return (
    <section className="contacts" id="contacts">
      <div className="container contacts__inner">
        <Reveal className="contacts__info">
          <p className="section-eyebrow"><T ru="СВЯЖИТЕСЬ С НАМИ" kz="БАЙЛАНЫСҚА ШЫҒУ" /></p>
          <h2 className="section-title"><T ru="Спланируйте той уже сегодня" kz="Тойыңызды бүгін жоспарлаңыз" /></h2>
          <p className="section-desc"><T ru="Оставьте заявку — мы свяжемся с вами в течение 30 минут" kz="Өтінім қалдырыңыз — 30 минут ішінде хабарласамыз" /></p>

          <ul className="contacts__list">
            <li><span className="contacts__icon">📞</span><a href="tel:+77001234567">+7 (700) 123-45-67</a></li>
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
          <button type="submit" className="btn btn--gold btn--block">
            <T ru="Отправить заявку" kz="Өтінім жіберу" />
          </button>
          <p className={`form-success${submitted ? ' is-visible' : ''}`}>
            <T ru="Спасибо! Мы скоро свяжемся с вами." kz="Рахмет! Жақын арада хабарласамыз." />
          </p>
        </Reveal>
      </div>
    </section>
  );
}
