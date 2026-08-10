'use client';

import { useEffect, useMemo, useState } from 'react';
import Reveal from '@/components/Reveal';
import { T } from '@/context/AppProviders';
import { fetchClients } from '@/lib/clientsApi';
import { mediaUrl } from '@/lib/media';

// Repeat the logo list so a single lap of the track is always wide enough
// to fill the viewport — otherwise 1-2 logos would leave visible gaps
// before the loop restarts.
const MIN_ITEMS_PER_LAP = 10;

export default function Clients() {
  const [clients, setClients] = useState([]);

  useEffect(() => {
    fetchClients().then(setClients);
  }, []);

  const lap = useMemo(() => {
    if (clients.length === 0) return [];
    const repeat = Math.max(1, Math.ceil(MIN_ITEMS_PER_LAP / clients.length));
    return Array.from({ length: repeat }, () => clients).flat();
  }, [clients]);

  if (clients.length === 0) return null;

  // Rendered twice back-to-back: animating the track from 0 to -50% moves
  // through exactly one full lap, and the second (identical) copy is
  // already in place to continue the loop with no visible jump.
  const track = [...lap, ...lap];

  return (
    <section className="clients" id="clients">
      <div className="container">
        <Reveal as="p" className="section-eyebrow"><T ru="НАМ ДОВЕРЯЮТ" kz="БІЗГЕ СЕНЕДІ" /></Reveal>
        <Reveal as="h2" className="section-title"><T ru="Наши клиенты" kz="Біздің клиенттер" /></Reveal>
      </div>

      <Reveal className="clients__marquee">
        <div className="clients__track">
          {track.map((cl, i) => (
            <div className="clients__logo" key={`${cl.id}-${i}`}>
              <img src={mediaUrl(cl.photo_url)} alt="" loading="lazy" />
            </div>
          ))}
        </div>
      </Reveal>
    </section>
  );
}
