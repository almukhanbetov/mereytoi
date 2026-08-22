'use client';

import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';

// Каждый пункт пакета — гибкая схема: title (основной пункт), note (короткая
// подпись под ним), groups (вложенные подсписки с меткой), duration
// (продолжительность, выделяется отдельно), extra (короткая доп. подпись).
const PACKAGES = [
  {
    id: 'standard',
    variant: 'standard',
    nameRu: 'Стандарт', nameKz: 'Стандарт',
    price: 300000,
    features: [
      { titleRu: 'Ведущий', titleKz: 'Жүргізуші' },
      { titleRu: 'Диджей', titleKz: 'Диджей' },
    ],
  },
  {
    id: 'premium1',
    variant: 'premium1',
    nameRu: 'Премиум 1', nameKz: 'Премиум 1',
    price: 590000,
    badgeRu: 'Акция', badgeKz: 'Акция',
    features: [
      { titleRu: 'Ведущий (Асаба)', titleKz: 'Жүргізуші (Асаба)' },
      { titleRu: 'Диджей, певец', titleKz: 'Диджей, әнші' },
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
        titleRu: 'Afro Show — дуэт', titleKz: 'Afro Show — дуэт',
        noteRu: 'Тёмнокожие артисты', noteKz: 'Афро әртістер',
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
    ],
  },
  {
    id: 'premium2',
    variant: 'premium2',
    nameRu: 'Премиум 2', nameKz: 'Премиум 2',
    price: 690000,
    badgeRu: 'Акция', badgeKz: 'Акция',
    features: [
      { titleRu: 'Ведущий (Асаба)', titleKz: 'Жүргізуші (Асаба)' },
      { titleRu: 'Диджей, певец', titleKz: 'Диджей, әнші' },
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
    features: [
      { titleRu: 'Ведущий', titleKz: 'Жүргізуші' },
      { titleRu: 'Диджей', titleKz: 'Диджей' },
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

function FeatureItem({ f }) {
  return (
    <li className="pricing-card__feature">
      <p className="pricing-card__feature-title">
        <T ru={f.titleRu} kz={f.titleKz} />
      </p>
      {(f.noteRu || f.noteKz) && (
        <p className="pricing-card__feature-note"><T ru={f.noteRu} kz={f.noteKz} /></p>
      )}
      {f.groups?.map((g) => (
        <div className="pricing-card__feature-groups" key={g.labelRu}>
          <span className="pricing-card__feature-group-label"><T ru={g.labelRu} kz={g.labelKz} /></span>
          <ul className="pricing-card__feature-group-items">
            {g.itemsRu.map((item, idx) => (
              <li key={item}><T ru={item} kz={g.itemsKz[idx]} /></li>
            ))}
          </ul>
        </div>
      ))}
      {(f.durationRu || f.durationKz) && (
        <span className="pricing-card__duration">
          <T ru={f.durationRu} kz={f.durationKz} />
        </span>
      )}
      {(f.extraRu || f.extraKz) && (
        <p className="pricing-card__extra"><T ru={f.extraRu} kz={f.extraKz} /></p>
      )}
    </li>
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
            <Reveal
              as="article"
              className={`pricing-card pricing-card--${p.variant}`}
              key={p.id}
              delay={i * 90}
            >
              <div className="pricing-card__head">
                <p className="pricing-card__name"><T ru={p.nameRu} kz={p.nameKz} /></p>
                <p className="pricing-card__price">
                  {p.priceFrom && <span className="pricing-card__price-from"><T ru="от " kz="" /></span>}
                  {formatPrice(p.price)}
                  {p.priceFrom && <span className="pricing-card__price-from"><T ru="" kz=" бастап" /></span>}
                </p>
                {(p.badgeRu || p.badgeKz) && (
                  <span className="pricing-card__badge"><T ru={p.badgeRu} kz={p.badgeKz} /></span>
                )}
              </div>

              <ul className="pricing-card__features">
                {p.features.map((f) => (
                  <FeatureItem f={f} key={f.titleRu} />
                ))}
              </ul>

              <div className="pricing-card__cta">
                <Link href="/#contacts" className="btn btn--gold btn--block">
                  <T ru="Оставить заявку" kz="Өтінім қалдыру" />
                </Link>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
