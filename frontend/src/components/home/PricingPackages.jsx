'use client';

import { useState } from 'react';
import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';

// shortList — то, что видно сразу, закрытая карточка (короткое, сканируемое).
// details — та же гибкая схема, что и раньше (title/note/groups/duration/extra),
// уходит под "Подробнее"; ничего из неё не удалено, только скрыто по умолчанию.
// Пакеты без скрытых подробностей (Стандарт) details не получают — тогда
// тоггл "Подробнее" вообще не рендерится, чтобы не открывать пустоту.
const PACKAGES = [
  {
    id: 'standard',
    variant: 'standard',
    nameRu: 'Стандарт', nameKz: 'Стандарт',
    price: 300000,
    shortList: [
      { ru: 'Ведущий', kz: 'Жүргізуші' },
      { ru: 'Диджей', kz: 'Диджей' },
      { ru: 'Видеограф + фотограф', kz: 'Видеограф + фотограф', notIncluded: true },
      { ru: 'Шоу-балет', kz: 'Шоу-балет', notIncluded: true },
      { ru: 'Afro Show', kz: 'Afro Show', notIncluded: true },
    ],
  },
  {
    id: 'premium2',
    variant: 'premium2',
    nameRu: 'Премиум', nameKz: 'Премиум',
    price: 690000,
    badgeRu: 'Акция', badgeKz: 'Акция',
    featuredRu: 'Рекомендуем', featuredKz: 'Ұсынамыз',
    shortList: [
      { ru: 'Ведущий (Асаба)', kz: 'Жүргізуші (Асаба)' },
      { ru: 'Диджей, певец', kz: 'Диджей, әнші' },
      { ru: 'Видеограф + фотограф', kz: 'Видеограф + фотограф' },
      { ru: 'Шоу-балет', kz: 'Шоу-балет' },
      { ru: 'Afro Show', kz: 'Afro Show' },
      { ru: 'Этно-ансамбль', kz: 'Этно-ансамбль' },
    ],
    details: [
      {
        titleRu: 'Видеограф + фотограф', titleKz: 'Видеограф + фотограф',
        noteRu: 'Полный монтаж + запись на флешку', noteKz: 'Толық монтаж + флешкаға жазу',
      },
      {
        titleRu: 'Танцовщицы — 4 девушки, шоу-балет', titleKz: 'Билеушілер — 4 қыз, шоу-балет',
        groups: [
          {
            labelRu: '3 танца', labelKz: '3 би',
            itemsRu: ['казахский', 'ретро', 'интерактивный танец с гостями'],
            itemsKz: ['қазақша', 'ретро', 'қонақтармен интерактивті би'],
          },
          {
            labelRu: 'Также', labelKz: 'Сондай-ақ',
            itemsRu: ['сопровождение құдалар', 'сопровождение молодожёнов'],
            itemsKz: ['құдаларды сүйемелдеу', 'жас жұбайларды сүйемелдеу'],
          },
        ],
      },
      {
        titleRu: 'Afro Show', titleKz: 'Afro Show',
        groups: [
          {
            labelRu: 'Программа', labelKz: 'Бағдарлама',
            itemsRu: ['попурри', 'диско 90-х', 'восточные композиции', 'тойские хиты'],
            itemsKz: ['попурри', '90-жылдар дискосы', 'шығыс композициялары', 'той хиттері'],
          },
        ],
        durationRu: '20–25 минут', durationKz: '20–25 минут',
        extraRu: 'Дополнительно: фотосессия', extraKz: 'Қосымша: фотосессия',
      },
      {
        titleRu: 'Этно-ансамбль', titleKz: 'Этно-ансамбль',
        groups: [
          {
            labelRu: 'Включает', labelKz: 'Құрамында',
            itemsRu: [
              'фуршет',
              'вывод құдалар с песней «Құдалар»',
              'сопровождение юбиляра',
              'музыкальное сопровождение во время первого горячего',
            ],
            itemsKz: [
              'фуршет',
              '«Құдалар» әнімен құдаларды шығару',
              'мерейтой иесін сүйемелдеу',
              'бірінші ыстық тағам кезінде музыкалық сүйемелдеу',
            ],
          },
        ],
      },
    ],
  },
  {
    id: 'vip',
    variant: 'vip',
    nameRu: 'VIP', nameKz: 'VIP',
    price: 1050000,
    priceFrom: true,
    shortList: [
      { ru: 'Ведущий', kz: 'Жүргізуші' },
      { ru: 'Диджей', kz: 'Диджей' },
      { ru: 'Двухкамерная съёмка + фотограф', kz: 'Екі камералы түсірілім + фотограф' },
      { ru: 'Шоу-балет', kz: 'Шоу-балет' },
      { ru: 'Live Band', kz: 'Live Band' },
      { ru: 'Jigits', kz: 'Jigits' },
    ],
    details: [
      {
        titleRu: 'Двухкамерная съёмка + фотограф', titleKz: 'Екі камералы түсірілім + фотограф',
        noteRu: 'Полный монтаж + запись на флешку', noteKz: 'Толық монтаж + флешкаға жазу',
      },
      {
        titleRu: 'Танцовщицы / шоу-балет', titleKz: 'Билеушілер / шоу-балет',
        groups: [
          {
            labelRu: 'Включает', labelKz: 'Құрамында',
            itemsRu: ['сопровождение құдалар', 'сопровождение юбиляра'],
            itemsKz: ['құдаларды сүйемелдеу', 'мерейтой иесін сүйемелдеу'],
          },
        ],
      },
      { titleRu: 'Live Band', titleKz: 'Live Band', noteRu: 'Живой инструментальный ансамбль', noteKz: 'Тірі аспаптық ансамбль' },
      {
        titleRu: 'Вокально-танцевальная группа «Jigits»', titleKz: '«Jigits» вокалды-би тобы',
        noteRu: 'Танцевальные попурри', noteKz: 'Би попурриі',
        durationRu: '30 минут', durationKz: '30 минут',
      },
    ],
  },
];

function DetailItem({ f }) {
  return (
    <li className="pricing-card__detail">
      <p className="pricing-card__detail-title"><T ru={f.titleRu} kz={f.titleKz} /></p>
      {(f.noteRu || f.noteKz) && (
        <p className="pricing-card__detail-note"><T ru={f.noteRu} kz={f.noteKz} /></p>
      )}
      {f.groups?.map((g) => (
        <div className="pricing-card__detail-groups" key={g.labelRu}>
          <span className="pricing-card__detail-group-label"><T ru={g.labelRu} kz={g.labelKz} /></span>
          <ul className="pricing-card__detail-group-items">
            {g.itemsRu.map((item, idx) => (
              <li key={item}><T ru={item} kz={g.itemsKz[idx]} /></li>
            ))}
          </ul>
        </div>
      ))}
      {(f.durationRu || f.durationKz) && (
        <span className="pricing-card__duration"><T ru={f.durationRu} kz={f.durationKz} /></span>
      )}
      {(f.extraRu || f.extraKz) && (
        <p className="pricing-card__detail-extra"><T ru={f.extraRu} kz={f.extraKz} /></p>
      )}
    </li>
  );
}

function PricingCard({ p, delay }) {
  const [open, setOpen] = useState(false);
  const hasDetails = p.details && p.details.length > 0;

  return (
    <Reveal as="article" className={`pricing-card pricing-card--${p.variant}`} delay={delay}>
      <div className="pricing-card__body">
        <p className="pricing-card__name"><T ru={p.nameRu} kz={p.nameKz} /></p>

        <p className="pricing-card__price">
          {p.priceFrom && <span className="pricing-card__price-from"><T ru="от" kz="" /></span>}
          <span className="pricing-card__price-amount">{p.price.toLocaleString('ru-RU')}</span>
          <span className="pricing-card__price-currency">₸</span>
          {p.priceFrom && <span className="pricing-card__price-from"><T ru="" kz="бастап" /></span>}
        </p>

        {(p.badgeRu || p.featuredRu) && (
          <div className="pricing-card__badges">
            {p.badgeRu && <span className="pricing-card__badge"><T ru={p.badgeRu} kz={p.badgeKz} /></span>}
            {p.featuredRu && (
              <span className="pricing-card__badge pricing-card__badge--featured">
                <T ru={p.featuredRu} kz={p.featuredKz} />
              </span>
            )}
          </div>
        )}

        <ul className="pricing-card__shortlist">
          {p.shortList.map((item) => (
            <li key={item.ru} className={item.notIncluded ? 'is-not-included' : undefined}>
              {item.notIncluded ? (
                <span className="pricing-card__check pricing-card__check--empty" aria-hidden="true" />
              ) : (
                <span className="pricing-card__check" aria-hidden="true">✓</span>
              )}
              <T ru={item.ru} kz={item.kz} />
            </li>
          ))}
        </ul>
      </div>

      <div className="pricing-card__footer">
        {hasDetails && (
          <>
            <button
              type="button"
              className="pricing-card__toggle"
              onClick={() => setOpen((v) => !v)}
              aria-expanded={open}
            >
              <T ru={open ? 'Скрыть' : 'Подробнее'} kz={open ? 'Жасыру' : 'Толығырақ'} />
              <span className="pricing-card__toggle-icon" aria-hidden="true">{open ? '−' : '+'}</span>
            </button>

            <div className={`pricing-card__details${open ? ' is-open' : ''}`}>
              <div className="pricing-card__details-inner">
                <ul className="pricing-card__detail-list">
                  {p.details.map((f) => (
                    <DetailItem f={f} key={f.titleRu} />
                  ))}
                </ul>
              </div>
            </div>
          </>
        )}

        <Link href="/#contacts" className="btn btn--gold btn--block">
          <T ru="Оставить заявку" kz="Өтінім қалдыру" />
        </Link>
      </div>
    </Reveal>
  );
}

export default function PricingPackages() {
  return (
    <section className="pricing" id="pricing">
      <div className="container">
        <Reveal as="p" className="section-eyebrow">
          <T ru="ФОРМАТЫ И ЦЕНЫ" kz="ФОРМАТТАР МЕН БАҒАЛАР" />
        </Reveal>
        <Reveal as="h2" className="section-title">
          <T ru="Ценовые пакеты" kz="Баға пакеттері" />
        </Reveal>
        <Reveal as="p" className="section-desc">
          <T ru="Выберите формат вашего торжества" kz="Тойыңыздың форматын таңдаңыз" />
        </Reveal>

        <div className="pricing__grid">
          {PACKAGES.map((p, i) => (
            <PricingCard p={p} delay={i * 90} key={p.id} />
          ))}
        </div>
      </div>
    </section>
  );
}
