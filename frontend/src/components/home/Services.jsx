'use client';

import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';

const SERVICES = [
  {
    ru: 'Полная организация тоя', kz: 'Тойды толық ұйымдастыру',
    descRu: 'От идеи до последнего момента — берём на себя весь процесс подготовки',
    descKz: 'Идеядан бастап соңғы сәтке дейін — барлық процесті өз мойнымызға аламыз',
    path: 'M24 4l4 10 10 2-7 8 2 10-9-5-9 5 2-10-7-8 10-2z',
  },
  {
    ru: 'Оформление и декор', kz: 'Безендіру және декор',
    descRu: 'Авторские решения оформления в современном и традиционном стиле',
    descKz: 'Заманауи және дәстүрлі стильдегі авторлық безендіру шешімдері',
    path: 'M24 6c-9 0-16 7-16 16s7 16 16 16 16-7 16-16S33 6 24 6zM24 14v10l7 4',
  },
  {
    ru: 'Банкетный зал', kz: 'Банкет залы',
    descRu: 'Подбор лучших залов вместимостью до 500 гостей',
    descKz: '500 қонаққа дейін сыйымдылығы бар үздік залдардан таңдау',
    rect: true,
  },
  {
    ru: 'Ведущий и шоу-программа', kz: 'Жүргізуші және шоу-бағдарлама',
    descRu: 'Опытные ведущие, артисты и файер-шоу',
    descKz: 'Тәжірибелі жүргізушілер, әртістер және от-шоу',
    mountain: true,
  },
  {
    ru: 'Фото и видеосъёмка', kz: 'Фото және видео түсіру',
    descRu: 'Команда профессиональных фотографов и видеографов, монтаж в день события',
    descKz: 'Кәсіби фотограф пен видеограф командасы, сол күні монтаж',
    camera: true,
  },
  {
    ru: 'Кейтеринг', kz: 'Кейтеринг',
    descRu: 'Национальная и европейская кухня, меню на любой вкус',
    descKz: 'Ұлттық және еуропалық асхана, әр дәмге лайық мәзір',
    bowl: true,
  },
];

function ServiceIcon({ s }) {
  if (s.rect) {
    return (
      <svg viewBox="0 0 48 48">
        <rect x="6" y="16" width="36" height="24" rx="2" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M6 16l18-10 18 10" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
      </svg>
    );
  }
  if (s.mountain) {
    return (
      <svg viewBox="0 0 48 48">
        <path d="M8 40l8-24 8 16 6-10 10 18z" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
        <circle cx="16" cy="10" r="4" fill="none" stroke="currentColor" strokeWidth="2" />
      </svg>
    );
  }
  if (s.camera) {
    return (
      <svg viewBox="0 0 48 48">
        <rect x="6" y="12" width="36" height="26" rx="3" fill="none" stroke="currentColor" strokeWidth="2" />
        <circle cx="24" cy="25" r="7" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M16 12l3-5h10l3 5" fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
      </svg>
    );
  }
  if (s.bowl) {
    return (
      <svg viewBox="0 0 48 48">
        <path d="M10 20c0-6 6-10 14-10s14 4 14 10-6 18-14 18-14-12-14-18z" fill="none" stroke="currentColor" strokeWidth="2" />
        <path d="M14 20h20" stroke="currentColor" strokeWidth="2" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 48 48">
      <path d={s.path} fill="none" stroke="currentColor" strokeWidth="2" strokeLinejoin="round" />
    </svg>
  );
}

export default function Services() {
  return (
    <section className="services" id="services">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="ЧТО МЫ ПРЕДЛАГАЕМ" kz="НЕ ҰСЫНАМЫЗ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Услуги" kz="Қызметтер" /></Reveal>
        <Reveal as="p" className="section-desc">
          <T ru="От полной организации до мельчайших деталей — уделяем внимание каждому моменту вашего торжества" kz="Толық ұйымдастырудан бастап шағын детальдарға дейін — тойыңыздың әр сәтіне мән береміз" />
        </Reveal>

        <div className="services__grid">
          {SERVICES.map((s, i) => (
            <Reveal as="article" className="card" key={s.ru} delay={(i % 4) * 70}>
              <div className="card__icon"><ServiceIcon s={s} /></div>
              <h3><T ru={s.ru} kz={s.kz} /></h3>
              <p><T ru={s.descRu} kz={s.descKz} /></p>
            </Reveal>
          ))}
        </div>

        <Reveal className="services__cta">
          <Link href="/services" className="btn btn--outline">
            <T ru="Смотреть каталог услуг" kz="Қызметтер каталогын көру" />
          </Link>
        </Reveal>
      </div>
    </section>
  );
}
