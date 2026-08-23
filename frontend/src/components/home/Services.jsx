'use client';

import Link from 'next/link';
import Reveal from '@/components/Reveal';
import ServiceCard from '@/components/services/ServiceCard';
import { T, useLang } from '@/context/AppProviders';

export default function Services({ listings = [], categories = [] }) {
  const { lang } = useLang();
  const categoryById = new Map(categories.map((c) => [c.id, c]));

  return (
    <section className="services" id="services">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="ЧТО МЫ ПРЕДЛАГАЕМ" kz="НЕ ҰСЫНАМЫЗ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Услуги" kz="Қызметтер" /></Reveal>
        <Reveal as="p" className="section-desc">
          <T ru="От полной организации до мельчайших деталей — уделяем внимание каждому моменту вашего торжества" kz="Толық ұйымдастырудан бастап шағын детальдарға дейін — тойыңыздың әр сәтіне мән береміз" />
        </Reveal>

        {listings.length > 0 ? (
          <div className="services__grid">
            {listings.map((l, i) => (
              <ServiceCard
                key={l.id}
                listing={l}
                categoryLabel={lang === 'kz' ? categoryById.get(l.category_id)?.name_kz : categoryById.get(l.category_id)?.name_ru}
                delay={(i % 3) * 70}
              />
            ))}
          </div>
        ) : (
          <p className="listing-empty"><T ru="Услуги скоро появятся" kz="Қызметтер жақында қосылады" /></p>
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
