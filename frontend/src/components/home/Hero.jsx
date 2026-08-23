'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';

// Falls back to the same values the stats block originally had hardcoded,
// in case the `statistics` prop is missing (e.g. the API was unreachable
// during server render).
const DEFAULT_STATISTICS = { events_count: 250, happy_guests_count: 15000, years_experience: 8, cities_count: 5 };

function StatCounter({ target }) {
  const ref = useRef(null);
  const [value, setValue] = useState(0);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let started = false;
    const io = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !started) {
          started = true;
          const duration = 1600;
          const start = performance.now();
          function tick(now) {
            const progress = Math.min((now - start) / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 3);
            setValue(Math.floor(eased * target));
            if (progress < 1) requestAnimationFrame(tick);
            else setValue(target);
          }
          requestAnimationFrame(tick);
          io.disconnect();
        }
      },
      { threshold: 0.4 }
    );
    io.observe(el);
    return () => io.disconnect();
  }, [target]);

  return <span className="stat__num" ref={ref}>{value.toLocaleString('ru-RU')}</span>;
}

export default function Hero({ statistics }) {
  const s = statistics || DEFAULT_STATISTICS;
  const STATS = [
    { count: s.events_count, ru: 'Проведено тоев', kz: 'Өткізілген той' },
    { count: s.happy_guests_count, ru: 'Довольных гостей', kz: 'Риза қонақтар' },
    { count: s.years_experience, ru: 'Лет опыта', kz: 'Жыл тәжірибе' },
    { count: s.cities_count, ru: 'Городов', kz: 'Қала' },
  ];

  return (
    <section className="hero" id="hero">
      <div className="hero__bg">
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="hero__blob hero__blob--3"></div>
        <svg className="hero__ornament" viewBox="0 0 1200 120" preserveAspectRatio="none" aria-hidden="true">
          <path d="M0,60 Q30,10 60,60 T120,60 T180,60 T240,60 T300,60 T360,60 T420,60 T480,60 T540,60 T600,60 T660,60 T720,60 T780,60 T840,60 T900,60 T960,60 T1020,60 T1080,60 T1140,60 T1200,60" fill="none" stroke="url(#goldline)" strokeWidth="1.5" />
          <defs>
            <linearGradient id="goldline" x1="0" y1="0" x2="1" y2="0">
              <stop offset="0" stopColor="#d4af6a" stopOpacity="0" />
              <stop offset="0.5" stopColor="#f3d9a4" stopOpacity="0.9" />
              <stop offset="1" stopColor="#d4af6a" stopOpacity="0" />
            </linearGradient>
          </defs>
        </svg>
      </div>

      <div className="container hero__inner">
        <Reveal as="p" className="hero__eyebrow">
          <T ru="АГЕНТСТВО ТОРЖЕСТВ · КАЗАХСТАН" kz="ТОЙ АГЕНТТІГІ · ҚАЗАҚСТАН" />
        </Reveal>
        <Reveal as="h1" className="hero__title">
          <span className="hero__title-line">MEREY<em>TOI</em></span>
        </Reveal>
        <Reveal as="p" className="hero__subtitle">
          <T ru="Создаём той вашей мечты, где традиции соединяются с современным стилем" kz="Дәстүр мен заманауи сәнді ұштастырған, армандаған тойыңызды жасаймыз" />
        </Reveal>

        <Reveal className="hero__actions">
          <a href="#contacts" className="btn btn--gold">
            <T ru="Оставить заявку" kz="Өтінім қалдыру" />
          </a>
          <Link href="/services" className="btn btn--outline"><T ru="Рассчитать стоимость" kz="Құнын есептеу" /></Link>
        </Reveal>

        <Reveal className="hero__stats">
          {STATS.map((s) => (
            <div className="stat" key={s.ru}>
              <span className="stat__row">
                <StatCounter target={s.count} />
                <span className="stat__plus">+</span>
              </span>
              <span className="stat__label"><T ru={s.ru} kz={s.kz} /></span>
            </div>
          ))}
        </Reveal>
      </div>

      <a href="#services" className="hero__scroll" aria-label="Scroll down">
        <span className="hero__scroll-dot"></span>
      </a>
    </section>
  );
}
