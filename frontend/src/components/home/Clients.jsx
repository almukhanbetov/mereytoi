'use client';

import { useEffect, useState } from 'react';
import Reveal from '@/components/Reveal';
import { T, useLang } from '@/context/AppProviders';
import { fetchClients } from '@/lib/clientsApi';
import { mediaUrl } from '@/lib/media';

const EVENT_LABELS = {
  wedding: { ru: 'Свадьба', kz: 'Үйлену тойы' },
  anniversary: { ru: 'Юбилей', kz: 'Мерейтой' },
  corporate: { ru: 'Корпоратив', kz: 'Корпоратив' },
};

export default function Clients() {
  const { lang } = useLang();
  const [clients, setClients] = useState([]);

  useEffect(() => {
    fetchClients().then(setClients);
  }, []);

  if (clients.length === 0) return null;

  return (
    <section className="clients" id="clients">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="НАМ ДОВЕРЯЮТ" kz="БІЗГЕ СЕНЕДІ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Наши клиенты" kz="Біздің клиенттер" /></Reveal>

        <div className="clients__grid">
          {clients.map((cl, i) => (
            <Reveal as="div" className="client-card" key={cl.id} delay={(i % 4) * 70}>
              <div
                className="client-card__photo"
                style={cl.photo_url ? { backgroundImage: `url(${mediaUrl(cl.photo_url)})` } : undefined}
              >
                {!cl.photo_url && cl.name?.[0]?.toUpperCase()}
              </div>
              <div className="client-card__body">
                <span className="client-card__badge">
                  {EVENT_LABELS[cl.event_type]?.[lang] || cl.event_type}
                </span>
                <p className="client-card__name">{cl.name}</p>
                {cl.quote && <p className="client-card__quote">«{cl.quote}»</p>}
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}
