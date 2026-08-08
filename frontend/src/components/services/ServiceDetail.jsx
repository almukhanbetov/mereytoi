'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import Reveal from '@/components/Reveal';
import ServiceCard from '@/components/services/ServiceCard';
import CommentsSection from '@/components/services/CommentsSection';
import { T, useLang, useCart } from '@/context/AppProviders';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';
import { flyToCart } from '@/lib/flyToCart';

export default function ServiceDetail({ listing, related }) {
  const { lang } = useLang();
  const { addItem } = useCart();
  const category = listing.category;
  const categoryLabel = category ? (lang === 'kz' ? category.name_kz : category.name_ru) : '';
  const images = listing.image_urls || [];
  const [activeImage, setActiveImage] = useState(0);
  const hasImages = images.length > 0;

  const isPerPerson = listing.min_guests > 0 && listing.max_guests > listing.min_guests;
  const [guests, setGuests] = useState(listing.min_guests || 1);
  const [added, setAdded] = useState(false);

  const total = useMemo(
    () => (isPerPerson ? guests * listing.price : listing.price),
    [isPerPerson, guests, listing.price]
  );

  function handleAddToCart(e) {
    addItem({
      listingId: listing.id,
      name: lang === 'kz' ? listing.name_kz : listing.name_ru,
      category: categoryLabel,
      emoji: listing.emoji,
      colorFrom: listing.color_from,
      colorTo: listing.color_to,
      image: images[0] || null,
      unitPrice: listing.price,
      guests: isPerPerson ? guests : null,
      totalPrice: total,
    });
    flyToCart(e.currentTarget);
    setAdded(true);
    setTimeout(() => setAdded(false), 2200);
  }

  return (
    <>
      <section className="page-hero" style={{ padding: '140px 0 0' }}>
        <div className="hero__blob hero__blob--1"></div>
        <div className="container">
          <p className="breadcrumb">
            <Link href="/"><T ru="Главная" kz="Басты бет" /></Link>
            <span>/</span>
            <Link href="/services"><T ru="Услуги" kz="Қызметтер" /></Link>
            <span>/</span>
            <span className="is-current">{lang === 'kz' ? listing.name_kz : listing.name_ru}</span>
          </p>
        </div>
      </section>

      <section className="product-detail">
        <div className="container product-detail__inner">
          <div>
            <div
              className="product-detail__media"
              style={
                hasImages
                  ? { backgroundImage: `url(${mediaUrl(images[activeImage])})`, backgroundSize: 'cover', backgroundPosition: 'center' }
                  : { background: `linear-gradient(150deg, ${listing.color_from || '#20222c'}, ${listing.color_to || '#3a3f52'})` }
              }
            >
              {!hasImages && <span style={{ position: 'relative', zIndex: 1 }}>{listing.emoji || '✨'}</span>}
            </div>

            {images.length > 1 && (
              <div className="service-gallery">
                {images.map((url, i) => (
                  <button
                    key={url}
                    type="button"
                    className={`service-gallery__thumb${i === activeImage ? ' is-active' : ''}`}
                    style={{ backgroundImage: `url(${mediaUrl(url)})` }}
                    onClick={() => setActiveImage(i)}
                    aria-label={`Фото ${i + 1}`}
                  />
                ))}
              </div>
            )}
          </div>

          <div className="product-detail__info">
            <span className="product-detail__cat">{categoryLabel}</span>
            <h1 className="product-detail__title">{lang === 'kz' ? listing.name_kz : listing.name_ru}</h1>

            {!isPerPerson && (
              <div className="product-detail__price">
                {listing.price > 0 ? formatPrice(listing.price) : <T ru="Цена по запросу" kz="Баға сұраныс бойынша" />}
                {listing.rating > 0 && (
                  <span style={{ fontSize: 16, marginLeft: 14, color: 'var(--gold)' }}>★ {listing.rating.toFixed(1)}</span>
                )}
              </div>
            )}
            {isPerPerson && listing.rating > 0 && (
              <div style={{ color: 'var(--gold)', fontSize: 16, marginBottom: 8 }}>★ {listing.rating.toFixed(1)}</div>
            )}

            <p className="product-detail__desc">{lang === 'kz' ? listing.description_kz : listing.description_ru}</p>

            <ul className="contacts__list" style={{ marginBottom: 30 }}>
              {listing.city && <li><span className="contacts__icon">📍</span><span>{listing.city}</span></li>}
              {listing.phone && <li><span className="contacts__icon">📞</span><a href={`tel:${listing.phone.replace(/\s/g, '')}`}>{listing.phone}</a></li>}
            </ul>

            {isPerPerson ? (
              <div className="booking-calc">
                <div className="booking-calc__row">
                  <span className="booking-calc__label"><T ru="Количество гостей" kz="Қонақтар саны" /></span>
                  <span className="booking-calc__guests">{guests} <T ru="чел." kz="адам" /></span>
                </div>
                <input
                  type="range"
                  min={listing.min_guests}
                  max={listing.max_guests}
                  value={guests}
                  onChange={(e) => setGuests(Number(e.target.value))}
                />
                <div className="booking-calc__range-labels">
                  <span>{listing.min_guests} <T ru="чел." kz="адам" /></span>
                  <span>{listing.max_guests} <T ru="чел." kz="адам" /></span>
                </div>

                <div className="booking-calc__total">
                  <div>
                    <div className="booking-calc__total-label"><T ru="Итоговая стоимость" kz="Жалпы құны" /></div>
                    <div className="booking-calc__unit">{guests} × {formatPrice(listing.price)}</div>
                  </div>
                  <div className="booking-calc__total-value">{formatPrice(total)}</div>
                </div>
              </div>
            ) : null}

            <div className="product-detail__actions" style={{ marginTop: 24 }}>
              {(isPerPerson || listing.price > 0) ? (
                <button type="button" className="btn btn--gold" onClick={handleAddToCart}>
                  <T ru="Добавить в корзину" kz="Себетке қосу" />
                </button>
              ) : (
                <a href="/#contacts" className="btn btn--gold">
                  <T ru="Оставить заявку" kz="Өтінім қалдыру" />
                </a>
              )}
            </div>
            <p className={`booking-added${added ? ' is-visible' : ''}`}>
              <T ru="Добавлено в корзину!" kz="Себетке қосылды!" />
            </p>
          </div>
        </div>
      </section>

      <CommentsSection listingId={listing.id} />

      {related.length > 0 && (
        <section className="related">
          <div className="container">
            <Reveal as="p" className="section-eyebrow"><T ru="ЕЩЁ В ЭТОЙ КАТЕГОРИИ" kz="ОСЫ САНАТТА ТАҒЫ" /></Reveal>
            <Reveal as="h2" className="section-title"><T ru="Похожие варианты" kz="Ұқсас нұсқалар" /></Reveal>
            <div className="product-grid">
              {related.map((l, i) => (
                <ServiceCard key={l.id} listing={l} categoryLabel={categoryLabel} delay={(i % 4) * 70} />
              ))}
            </div>
          </div>
        </section>
      )}
    </>
  );
}
