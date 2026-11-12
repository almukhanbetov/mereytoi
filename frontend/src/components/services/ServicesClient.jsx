'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import Reveal from '@/components/Reveal';
import ServiceCard from '@/components/services/ServiceCard';
import { T, useLang } from '@/context/AppProviders';
import { fetchFeedClient } from '@/lib/promotionApi';

// The catalog reads GET /api/listings/feed: the same category and name
// search as before, but filtered on the server so paid ads («Реклама»)
// always match what the visitor asked for, and paged («Показать ещё»).
export default function ServicesClient({ categories, initialPage }) {
  // Initial filter can arrive via ?category=<slug> (e.g. from the homepage
  // category cards) — read once on mount; the filter buttons below still
  // control it client-side afterwards exactly as before.
  const searchParams = useSearchParams();
  const [activeCat, setActiveCat] = useState(() => searchParams.get('category') || 'all');
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState(() => ({ cat: searchParams.get('category') || 'all', search: '' }));
  const [page, setPage] = useState(() => ({
    items: initialPage?.items || [],
    total: initialPage?.total || 0,
    nextCursor: initialPage?.nextCursor || null,
  }));
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const firstQuery = useRef(true);
  const generation = useRef(0);
  const { lang } = useLang();

  // Typing settles for a moment before it becomes a new query.
  useEffect(() => {
    const t = setTimeout(() => {
      const next = { cat: activeCat, search: search.trim() };
      setQuery((prev) => (prev.cat === next.cat && prev.search === next.search ? prev : next));
    }, 350);
    return () => clearTimeout(t);
  }, [activeCat, search]);

  useEffect(() => {
    // The server already rendered the first page of the initial query.
    if (firstQuery.current) {
      firstQuery.current = false;
      return;
    }
    const gen = ++generation.current;
    setLoading(true);
    fetchFeedClient({ category: query.cat, search: query.search })
      .then((p) => { if (gen === generation.current) setPage(p); })
      .catch(() => { if (gen === generation.current) setPage({ items: [], total: 0, nextCursor: null }); })
      .finally(() => { if (gen === generation.current) setLoading(false); });
  }, [query]);

  async function loadMore() {
    if (!page.nextCursor || loadingMore) return;
    const gen = generation.current;
    setLoadingMore(true);
    try {
      const next = await fetchFeedClient({ category: query.cat, search: query.search, cursor: page.nextCursor });
      if (gen !== generation.current) return;
      setPage((prev) => {
        const seen = new Set(prev.items.map((l) => l.id));
        return {
          items: [...prev.items, ...next.items.filter((l) => !seen.has(l.id))],
          total: next.total,
          nextCursor: next.nextCursor,
        };
      });
    } catch {
      // the button stays; another click retries
    } finally {
      setLoadingMore(false);
    }
  }

  const categoryById = useMemo(() => {
    const map = new Map();
    categories.forEach((c) => map.set(c.id, c));
    return map;
  }, [categories]);

  const filtered = page.items;

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
          <h1>
            <T
              ru="Организация той и мероприятий в Алматы"
              kz="Алматыда той және іс-шараларды ұйымдастыру"
            />
          </h1>
          <p>
            <T
              ru="Организация той, свадеб, юбилеев и корпоративов в Алматы: площадки, ведущие, декор, шоу-программы, артисты, фото и видео."
              kz="Алматыда той, үйлену тойы, мерейтой және корпоративтерді ұйымдастыру: алаңдар, жүргізушілер, декор, шоу-бағдарламалар, әртістер, фото және видео."
            />
          </p>
          <p style={{ marginTop: 18 }}>
            <T
              ru="Планируете полноценный той? Посмотрите отдельную страницу по организации той в Алматы."
              kz="Толық той ұйымдастыруды жоспарлап отырсыз ба? Алматыда той ұйымдастыруға арналған арнайы бетті қараңыз."
            />
          </p>
          <div className="services-links">
            <Link href="/toi-almaty" className="btn btn--outline btn--sm">
              <T ru="Организация той в Алматы" kz="Алматыда той ұйымдастыру" />
            </Link>
            <Link href="/wedding-almaty" className="btn btn--outline btn--sm">
              <T ru="Организация свадьбы в Алматы" kz="Алматыда үйлену тойын ұйымдастыру" />
            </Link>
            <Link href="/corporate-almaty" className="btn btn--outline btn--sm">
              <T ru="Организация корпоратива в Алматы" kz="Алматыда корпоратив ұйымдастыру" />
            </Link>
            <Link href="/yubiley-almaty" className="btn btn--outline btn--sm">
              <T ru="Организация юбилея в Алматы" kz="Алматыда мерейтой ұйымдастыру" />
            </Link>
          </div>
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

            {loading ? (
              <p className="listing-empty"><T ru="Загрузка…" kz="Жүктелуде…" /></p>
            ) : filtered.length === 0 ? (
              <p className="listing-empty"><T ru="Ничего не найдено" kz="Ешнәрсе табылмады" /></p>
            ) : (
              <>
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
              {page.nextCursor && (
                <div style={{ display: 'flex', justifyContent: 'center', marginTop: 28 }}>
                  <button type="button" className="btn btn--outline" onClick={loadMore} disabled={loadingMore}>
                    {loadingMore ? <T ru="Загрузка…" kz="Жүктелуде…" /> : <T ru="Показать ещё" kz="Тағы көрсету" />}
                  </button>
                </div>
              )}
              </>
            )}
          </div>
        </div>
      </section>
    </>
  );
}
