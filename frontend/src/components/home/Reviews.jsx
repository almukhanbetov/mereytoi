'use client';

import { useEffect, useRef, useState } from 'react';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';

const REVIEWS = [
  {
    ru: 'Команда MEREYTOI сделала нашу свадьбу даже красивее, чем мы мечтали. Каждая деталь была продумана!',
    kz: 'MEREYTOI командасы біздің үйлену тойымызды армандағанымыздан да әдемі етті. Әр деталь ойластырылған!',
    avatar: 'А', name: 'Айгерим & Данияр',
    metaRu: 'Свадьба, Алматы', metaKz: 'Үйлену тойы, Алматы',
  },
  {
    ru: 'Прекрасно провели юбилей моего отца. Уровень организации на высоте, всё вовремя!',
    kz: 'Әкемнің мерейтойын керемет өткіздік. Ұйымдастыру деңгейі жоғары, барлығы уақытында!',
    avatar: 'М', name: 'Мұрат Сериков',
    metaRu: 'Юбилей, Астана', metaKz: 'Мерейтой, Астана',
  },
  {
    ru: 'Организовали наш корпоративный вечер — гости до сих пор восхищаются.',
    kz: 'Корпоративтік кешімізді ұйымдастырды — қонақтар әлі күнге дейін мақтап жүр.',
    avatar: 'Д', name: 'Динара Ахметова',
    metaRu: 'Корпоратив, Шымкент', metaKz: 'Корпоратив, Шымкент',
  },
];

export default function Reviews() {
  const [current, setCurrent] = useState(0);
  const timerRef = useRef(null);

  function goTo(index) {
    setCurrent((index + REVIEWS.length) % REVIEWS.length);
  }

  useEffect(() => {
    clearInterval(timerRef.current);
    timerRef.current = setInterval(() => {
      setCurrent((c) => (c + 1) % REVIEWS.length);
    }, 6000);
    return () => clearInterval(timerRef.current);
  }, [current]);

  return (
    <section className="reviews" id="reviews">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="ОТЗЫВЫ КЛИЕНТОВ" kz="КЛИЕНТТЕР ПІКІРІ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Отзывы" kz="Пікірлер" /></Reveal>

        <Reveal className="reviews__slider">
          <div className="reviews__track" style={{ transform: `translateX(-${current * 100}%)` }}>
            {REVIEWS.map((r) => (
              <article className="review" key={r.name}>
                <div className="review__stars">★★★★★</div>
                <p className="review__text"><T ru={r.ru} kz={r.kz} /></p>
                <div className="review__author">
                  <span className="review__avatar">{r.avatar}</span>
                  <div>
                    <b>{r.name}</b>
                    <span><T ru={r.metaRu} kz={r.metaKz} /></span>
                  </div>
                </div>
              </article>
            ))}
          </div>

          <div className="reviews__controls">
            <button className="reviews__arrow" onClick={() => goTo(current - 1)} aria-label="Prev">‹</button>
            <div className="reviews__dots">
              {REVIEWS.map((_, i) => (
                <span
                  key={i}
                  className={i === current ? 'is-active' : ''}
                  onClick={() => goTo(i)}
                />
              ))}
            </div>
            <button className="reviews__arrow" onClick={() => goTo(current + 1)} aria-label="Next">›</button>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
