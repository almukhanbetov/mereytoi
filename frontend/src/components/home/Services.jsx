'use client';

import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';
import { mediaUrl } from '@/lib/media';

export default function Services({ categories = [] }) {
  return (
    <section className="services" id="services">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="ЧТО МЫ ПРЕДЛАГАЕМ" kz="НЕ ҰСЫНАМЫЗ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Услуги" kz="Қызметтер" /></Reveal>
        <Reveal as="p" className="section-desc">
          <T ru="От полной организации до мельчайших деталей — уделяем внимание каждому моменту вашего торжества" kz="Толық ұйымдастырудан бастап шағын детальдарға дейін — тойыңыздың әр сәтіне мән береміз" />
        </Reveal>

        {categories.length > 0 ? (
          <div className="categories__grid">
            {categories.map((c, i) => (
              <Reveal key={c.id} delay={(i % 3) * 70}>
                <Link href={`/services?category=${c.slug}`} className="category-card">
                  <div
                    className="category-card__media"
                    style={c.image_url ? { backgroundImage: `url(${mediaUrl(c.image_url)})` } : undefined}
                  >
                    {!c.image_url && <span className="category-card__fallback" aria-hidden="true">✨</span>}
                  </div>
                  <div className="category-card__body">
                    <h3 className="category-card__name"><T ru={c.name_ru} kz={c.name_kz} /></h3>
                    <span className="category-card__link">
                      <T ru="Смотреть услуги" kz="Қызметтерді қарау" /> →
                    </span>
                  </div>
                </Link>
              </Reveal>
            ))}
          </div>
        ) : (
          <p className="listing-empty"><T ru="Категории скоро появятся" kz="Санаттар жақында қосылады" /></p>
        )}

        <Reveal className="services__cta">
          <Link href="/services" className="btn btn--outline">
            <T ru="Смотреть каталог услуг" kz="Қызметтер каталогын көру" />
          </Link>
        </Reveal>
      </div>
    </section>
  );
}
