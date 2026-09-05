'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { T, useLang, useManagerChat } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { mediaUrl } from '@/lib/media';
import { formatPrice } from '@/lib/format';
import CommentThread from '@/components/profile/CommentThread';
import WsModal from '@/components/profile/WsModal';

const VOTE_ICONS = { up: '👍', maybe: '🤔', down: '👎' };
const MAX_COMPARE = 4;

function groupByCategory(candidates, lang) {
  const groups = new Map();
  for (const c of candidates) {
    const key = c.listing?.category?.id ?? 0;
    const label = (lang === 'kz' ? c.listing?.category?.name_kz : c.listing?.category?.name_ru) || (lang === 'kz' ? 'Басқа' : 'Другое');
    if (!groups.has(key)) groups.set(key, { label, items: [] });
    groups.get(key).items.push(c);
  }
  return Array.from(groups.values());
}

export default function EventServicesPage() {
  const { eventId, event, canEdit, refreshSummary } = useEventWorkspace();
  const { lang } = useLang();
  const { openChat } = useManagerChat();
  const [candidates, setCandidates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [compareIds, setCompareIds] = useState([]);
  const [compareOpen, setCompareOpen] = useState(false);
  const [threadCandidate, setThreadCandidate] = useState(null);

  const load = useCallback(async () => {
    const data = await eventsApi.candidates(eventId);
    setCandidates(data.candidates || []);
    setLoading(false);
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  async function handleVote(candidateId, value) {
    setCandidates((prev) => prev.map((c) => {
      if (c.id !== candidateId) return c;
      const votes = { ...c.votes };
      if (c.my_vote) votes[c.my_vote] = Math.max(0, (votes[c.my_vote] || 0) - 1);
      votes[value] = (votes[value] || 0) + 1;
      return { ...c, votes, my_vote: value };
    }));
    try {
      await eventsApi.vote(eventId, candidateId, value);
    } catch {
      load();
    }
  }

  async function handleStatus(candidateId, status) {
    try {
      await eventsApi.updateCandidateStatus(eventId, candidateId, status);
      await load();
      refreshSummary();
    } catch (err) {
      alert(err.message);
    }
  }

  async function handleRemove(candidateId) {
    const confirmText = lang === 'kz' ? 'Тізімнен алып тастау керек пе?' : 'Убрать из shortlist?';
    if (!window.confirm(confirmText)) return;
    try {
      await eventsApi.removeCandidate(eventId, candidateId);
      setCandidates((prev) => prev.filter((c) => c.id !== candidateId));
      refreshSummary();
    } catch (err) {
      alert(err.message);
    }
  }

  function toggleCompare(id) {
    setCompareIds((prev) => {
      if (prev.includes(id)) return prev.filter((x) => x !== id);
      if (prev.length >= MAX_COMPARE) return prev;
      return [...prev, id];
    });
  }

  const groups = groupByCategory(candidates, lang);
  const compareItems = candidates.filter((c) => compareIds.includes(c.id));
  const threadItem = candidates.find((c) => c.id === threadCandidate);

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 22, gap: 12, flexWrap: 'wrap' }}>
        <h2 className="ws-section-title" style={{ margin: 0 }}><T ru="Услуги" kz="Қызметтер" /></h2>
        <Link href="/services" className="btn btn--outline" style={{ padding: '10px 18px', fontSize: 13.5 }}>
          + <T ru="Добавить услугу" kz="Қызмет қосу" />
        </Link>
      </div>

      {loading && <div className="ws-skeleton" style={{ height: 300 }} />}

      {!loading && candidates.length === 0 && (
        <div className="ws-empty">
          <span className="ws-empty__icon">🎯</span>
          <h3 className="ws-empty__title"><T ru="Вы ещё ничего не выбрали" kz="Сіз әлі ештеңе таңдаған жоқсыз" /></h3>
          <p className="ws-empty__text">
            <T ru="Добавьте несколько вариантов из каталога, чтобы сравнить их вместе." kz="Бірге салыстыру үшін каталогтан бірнеше нұсқа қосыңыз." />
          </p>
          <Link href="/services" className="btn btn--gold"><T ru="Перейти к услугам" kz="Қызметтерге өту" /></Link>
        </div>
      )}

      {!loading && groups.map((group) => (
        <div key={group.label} style={{ marginBottom: 30 }}>
          <h3 style={{ fontSize: 12.5, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em', margin: '0 0 12px', fontWeight: 700 }}>
            {group.label} · {group.items.length}
          </h3>
          <div className="ws-candidate-list">
            {group.items.map((c) => {
              const listing = c.listing || {};
              const name = lang === 'kz' ? listing.name_kz : listing.name_ru;
              const cover = (listing.image_urls || [])[0];
              return (
                <div className="ws-candidate-card" key={c.id}>
                  {cover ? (
                    <img className="ws-candidate-card__media" src={mediaUrl(cover)} alt={name} />
                  ) : (
                    <div className="ws-candidate-card__media" />
                  )}
                  <div className="ws-candidate-card__body">
                    <div className="ws-candidate-card__top">
                      <div>
                        <h4 className="ws-candidate-card__name">{name}</h4>
                        <div className="ws-candidate-card__meta">
                          {listing.city}{listing.rating > 0 ? ` · ★ ${listing.rating.toFixed(1)}` : ''}
                          {c.status === 'selected' && <span className="ws-chip ws-chip--gold" style={{ marginLeft: 8 }}>✓ <T ru="выбрано" kz="таңдалды" /></span>}
                          {c.status === 'rejected' && <span className="ws-chip ws-chip--outline" style={{ marginLeft: 8 }}><T ru="отклонено" kz="қабылданбады" /></span>}
                        </div>
                      </div>
                      <div className="ws-candidate-card__price">{formatPrice(listing.price || 0)}</div>
                    </div>

                    <div className="ws-candidate-card__actions">
                      <div className="ws-vote-group">
                        {['up', 'maybe', 'down'].map((value) => (
                          <button
                            key={value}
                            type="button"
                            aria-pressed={c.my_vote === value}
                            className={`ws-vote-btn${c.my_vote === value ? ' is-mine' : ''}`}
                            onClick={() => handleVote(c.id, value)}
                          >
                            {VOTE_ICONS[value]} {c.votes?.[value] || 0}
                          </button>
                        ))}
                      </div>

                      <button type="button" className="ws-chip" onClick={() => setThreadCandidate(c.id)}>
                        💬 {c.comment_count || 0}
                      </button>

                      {/* Two distinct flows, never merged (brief section
                          21): the 💬 chip above opens the team's own
                          internal discussion; this opens the real manager
                          chat with this exact service (and event) already
                          attached as context. */}
                      <button
                        type="button"
                        className="admin-table__link"
                        onClick={() => openChat({
                          listingId: c.listing_id,
                          listingName: lang === 'kz' ? listing.name_kz : listing.name_ru,
                          listingPrice: listing.price,
                          eventId,
                          eventTitle: event.title,
                          eventDate: event.event_date,
                          eventCity: event.city,
                          eventGuests: event.guests,
                          eventBudget: event.budget_total,
                        })}
                      >
                        <T ru="Спросить MEREYTOI" kz="MEREYTOI-дан сұрау" />
                      </button>

                      <label className="ws-candidate-card__select">
                        <input
                          type="checkbox"
                          className="ws-candidate-card__checkbox"
                          checked={compareIds.includes(c.id)}
                          onChange={() => toggleCompare(c.id)}
                          disabled={!compareIds.includes(c.id) && compareIds.length >= MAX_COMPARE}
                        />
                        <T ru="Сравнить" kz="Салыстыру" />
                      </label>

                      {canEdit && (
                        <select className="ws-status-select" value={c.status} onChange={(e) => handleStatus(c.id, e.target.value)}>
                          <option value="shortlisted">{lang === 'kz' ? 'Талқылануда' : 'Обсуждается'}</option>
                          <option value="selected">{lang === 'kz' ? '✓ Таңдау' : '✓ Выбрать'}</option>
                          <option value="rejected">{lang === 'kz' ? 'Қабылдамау' : 'Отклонить'}</option>
                        </select>
                      )}

                      <Link href={`/services/${c.listing_id}`} className="admin-table__link" style={{ marginLeft: 'auto' }}>
                        <T ru="Открыть →" kz="Ашу →" />
                      </Link>

                      {canEdit && (
                        <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleRemove(c.id)}>
                          <T ru="Убрать" kz="Алып тастау" />
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}

      {compareIds.length >= 2 && (
        <div className="ws-compare-bar">
          <span>{compareIds.length} <T ru="выбрано для сравнения" kz="салыстыру үшін таңдалды" /></span>
          <button type="button" className="btn btn--gold" style={{ padding: '9px 20px', fontSize: 13.5 }} onClick={() => setCompareOpen(true)}>
            <T ru="Сравнить" kz="Салыстыру" />
          </button>
        </div>
      )}

      {compareOpen && (
        <WsModal title={<T ru="Сравнение" kz="Салыстыру" />} onClose={() => setCompareOpen(false)}>
          <CompareView items={compareItems} lang={lang} canEdit={canEdit} onSelect={(id) => { handleStatus(id, 'selected'); setCompareOpen(false); }} />
        </WsModal>
      )}

      {threadItem && (
        <WsModal
          title={lang === 'kz' ? threadItem.listing?.name_kz : threadItem.listing?.name_ru}
          onClose={() => setThreadCandidate(null)}
        >
          <CommentThread eventId={eventId} candidateId={threadItem.id} canWrite={canEdit} />
        </WsModal>
      )}
    </div>
  );
}

function CompareView({ items, lang, canEdit, onSelect }) {
  return (
    <>
      {/* Desktop: a real comparison table. Mobile: swipeable-feeling stacked
          cards instead of squeezing a wide table into a phone screen — see
          the breakpoint in globals.css. */}
      <div className="ws-compare-table-wrap ws-compare-desktop-only">
        <table className="ws-compare-table">
          <thead>
            <tr>
              <th><T ru="Услуга" kz="Қызмет" /></th>
              <th><T ru="Цена" kz="Бағасы" /></th>
              <th><T ru="Рейтинг" kz="Рейтинг" /></th>
              <th><T ru="Город" kz="Қала" /></th>
              <th><T ru="Голосов «За»" kz="«Жақтап»" /></th>
              {canEdit && <th></th>}
            </tr>
          </thead>
          <tbody>
            {items.map((c) => {
              const listing = c.listing || {};
              const name = lang === 'kz' ? listing.name_kz : listing.name_ru;
              return (
                <tr key={c.id}>
                  <td>{name}</td>
                  <td>{formatPrice(listing.price || 0)}</td>
                  <td>{listing.rating ? `★ ${listing.rating.toFixed(1)}` : '—'}</td>
                  <td>{listing.city || '—'}</td>
                  <td>{c.votes?.up || 0}</td>
                  {canEdit && (
                    <td>
                      <button type="button" className="btn btn--gold" style={{ padding: '7px 16px', fontSize: 13 }} onClick={() => onSelect(c.id)}>
                        <T ru="Выбрать" kz="Таңдау" />
                      </button>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <div className="ws-compare-cards ws-compare-mobile-only">
        {items.map((c) => {
          const listing = c.listing || {};
          const name = lang === 'kz' ? listing.name_kz : listing.name_ru;
          return (
            <div className="ws-compare-card" key={c.id}>
              <h4 style={{ margin: '0 0 10px', fontFamily: 'var(--font-playfair), serif', fontSize: 16 }}>{name}</h4>
              <div className="ws-compare-card__row"><span><T ru="Цена" kz="Бағасы" /></span><span>{formatPrice(listing.price || 0)}</span></div>
              <div className="ws-compare-card__row"><span><T ru="Рейтинг" kz="Рейтинг" /></span><span>{listing.rating ? `★ ${listing.rating.toFixed(1)}` : '—'}</span></div>
              <div className="ws-compare-card__row"><span><T ru="Город" kz="Қала" /></span><span>{listing.city || '—'}</span></div>
              <div className="ws-compare-card__row"><span><T ru="Голосов «За»" kz="«Жақтап» дауыс" /></span><span>{c.votes?.up || 0}</span></div>
              {canEdit && (
                <button type="button" className="btn btn--gold" style={{ width: '100%', marginTop: 14, padding: '10px' }} onClick={() => onSelect(c.id)}>
                  <T ru="Выбрать" kz="Таңдау" />
                </button>
              )}
            </div>
          );
        })}
      </div>
    </>
  );
}
