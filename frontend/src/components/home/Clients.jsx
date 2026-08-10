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
      <div className="clients__glow clients__glow--1" aria-hidden="true" />
      <div className="clients__glow clients__glow--2" aria-hidden="true" />

      <div className="container">
        <Reveal as="div" className="clients__accent" aria-hidden="true">
          <span className="clients__accent-line" />
          <span className="clients__accent-mark">✦</span>
          <span className="clients__accent-line" />
        </Reveal>

        <Reveal as="h2" className="clients__title">
          <T
            ru={<>Нам уже доверяют <span className="clients__title-highlight">лидеры рынка</span></>}
            kz={<>Бізге нарық <span className="clients__title-highlight">көшбасшылары</span> сенеді</>}
          />
        </Reveal>

        <Reveal className="clients__marquee">
          <div className="clients__track">
            {track.map((cl, i) => (
              <div className="clients__logo" key={`${cl.id}-${i}`}>
                <img src={mediaUrl(cl.photo_url)} alt="" loading="lazy" />
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}
