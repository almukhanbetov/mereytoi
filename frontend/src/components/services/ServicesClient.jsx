'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import Reveal from '@/components/Reveal';
import ServiceCard from '@/components/services/ServiceCard';
import { T, useLang } from '@/context/AppProviders';

export default function ServicesClient({ categories, listings }) {
  const [activeCat, setActiveCat] = useState('all');
  const [search, setSearch] = useState('');
  const { lang } = useLang();

  const categoryById = useMemo(() => {
    const map = new Map();
    categories.forEach((c) => map.set(c.id, c));
    return map;
  }, [categories]);

  const filtered = useMemo(() => {
    return listings.filter((l) => {
      if (activeCat !== 'all' && categoryById.get(l.category_id)?.slug !== activeCat) return false;
      if (search.trim()) {
        const term = search.trim().toLowerCase();
        const name = `${l.name_ru} ${l.name_kz}`.toLowerCase();
        if (!name.includes(term)) return false;
      }
      return true;
    });
  }, [listings, activeCat, search, categoryById]);

  return (
    <>
      <section className="page-hero">
        <div className="hero__blob hero__blob--1"></div>
        <div className="hero__blob hero__blob--2"></div>
        <div className="container">
          <p className="breadcrumb">
            <Link href="/"><T ru="Главная" kz="Басты бет" /></Link>
            <span>/</span>
            <span className="is-current"><T ru="Услуги" kz="Қызметтер" /></span>
          </p>
          <h1><T ru="Каталог услуг" kz="Қызметтер каталогы" /></h1>
          <p><T ru="Площадки, ведущие, шоу-программы, артисты и звёзды эстрады для вашего тоя" kz="Тойыңызға арналған алаңдар, жүргізушілер, шоу-бағдарламалар, әртістер және эстрада жұлдыздары" /></p>
        </div>
      </section>

      <section className="shop-layout">
        <div className="container shop-layout__inner">
          <aside className="shop-sidebar">
            <Reveal className="shop-sidebar__inner">
              <p className="shop-sidebar__title"><T ru="Каталоги" kz="Каталогтар" /></p>
              <nav className="shop-sidebar__list">
                <button className={`filter-btn${activeCat === 'all' ? ' is-active' : ''}`} onClick={() => setActiveCat('all')}>
                  <T ru="Все" kz="Барлығы" />
                </button>
                {categories.map((c) => (
                  <button
                    key={c.slug}
                    className={`filter-btn${activeCat === c.slug ? ' is-active' : ''}`}
                    onClick={() => setActiveCat(c.slug)}
                  >
                    {lang === 'kz' ? c.name_kz : c.name_ru}
                  </button>
                ))}
              </nav>
            </Reveal>
          </aside>

          <div className="shop-main">
            <div className="listing-search">
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder={lang === 'kz' ? 'Іздеу...' : 'Поиск...'}
              />
            </div>

            {filtered.length === 0 ? (
              <p className="listing-empty"><T ru="Ничего не найдено" kz="Ешнәрсе табылмады" /></p>
            ) : (
              <div className="product-grid">
                {filtered.map((l, i) => (
                  <ServiceCard
                    key={l.id}
                    listing={l}
                    categoryLabel={lang === 'kz' ? categoryById.get(l.category_id)?.name_kz : categoryById.get(l.category_id)?.name_ru}
                    delay={(i % 4) * 70}
                  />
                ))}
              </div>
            )}
          </div>
        </div>
      </section>
    </>
  );
}
