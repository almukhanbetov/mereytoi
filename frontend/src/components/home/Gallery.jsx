'use client';

import { useState } from 'react';
import Reveal from '@/components/Reveal';
import { T, useLang } from '@/context/AppProviders';

const FILTERS = [
  { id: 'all', ru: 'Все', kz: 'Барлығы' },
  { id: 'wedding', ru: 'Свадьбы', kz: 'Үйлену тойы' },
  { id: 'anniversary', ru: 'Юбилеи', kz: 'Мерейтой' },
  { id: 'corporate', ru: 'Корпоративы', kz: 'Корпоратив' },
];

const ITEMS = [
  { cat: 'wedding', h: 1.3, c1: '#3a1420', c2: '#d4af6a', icon: '💍', ru: 'Свадьба', kz: 'Үйлену тойы' },
  { cat: 'anniversary', h: 1, c1: '#142a3a', c2: '#f3d9a4', icon: '🎉', ru: 'Юбилей', kz: 'Мерейтой' },
  { cat: 'corporate', h: 1.5, c1: '#20301f', c2: '#d4af6a', icon: '🥂', ru: 'Корпоратив', kz: 'Корпоратив' },
  { cat: 'wedding', h: 1, c1: '#3a1420', c2: '#f3d9a4', icon: '💐', ru: 'Декор тоя', kz: 'Той безендіру' },
  { cat: 'wedding', h: 1.4, c1: '#1f1430', c2: '#d4af6a', icon: '✨', ru: 'Вечер тоя', kz: 'Той кеші' },
  { cat: 'anniversary', h: 1.1, c1: '#142a3a', c2: '#d4af6a', icon: '🎂', ru: 'Юбилейный той', kz: 'Мерейтой тойы' },
  { cat: 'corporate', h: 1, c1: '#20301f', c2: '#f3d9a4', icon: '🎤', ru: 'Мероприятие', kz: 'Іс-шара' },
  { cat: 'wedding', h: 1.35, c1: '#3a1420', c2: '#d4af6a', icon: '👰', ru: 'Невеста', kz: 'Қалыңдық' },
];

export default function Gallery() {
  const [active, setActive] = useState('all');
  const { lang } = useLang();

  return (
    <section className="gallery" id="gallery">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="НАШИ РАБОТЫ" kz="БІЗДІҢ ЖҰМЫСТАР" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Галерея" kz="Галерея" /></Reveal>
        <Reveal as="p" className="section-desc">
          <T ru="Несколько моментов с проведённых нами торжеств" kz="Өткізілген іс-шаралардың бірнеше сәттері" />
        </Reveal>

        <Reveal className="gallery__filters">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              className={`filter-btn${active === f.id ? ' is-active' : ''}`}
              onClick={() => setActive(f.id)}
            >
              {lang === 'kz' ? f.kz : f.ru}
            </button>
          ))}
        </Reveal>

        <div className="gallery__grid">
          {ITEMS.map((item, i) => (
            <Reveal
              as="div"
              key={i}
              className={`g-item${active !== 'all' && active !== item.cat ? ' is-hidden' : ''}`}
              style={{ '--h': item.h, '--c1': item.c1, '--c2': item.c2 }}
              delay={(i % 4) * 70}
            >
              <span className="g-item__icon">{item.icon}</span>
              <span className="g-item__label">{lang === 'kz' ? item.kz : item.ru}</span>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
