'use client';

import { useEffect, useState } from 'react';
import { T, useLang } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { formatPrice } from '@/lib/format';
import { candidateEstimate } from '@/lib/eventHelpers';

export default function EventBudgetPage() {
  const { eventId, event, canEdit, refreshEvent, refreshSummary } = useEventWorkspace();
  const { lang } = useLang();
  const [candidates, setCandidates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState(false);
  const [budgetInput, setBudgetInput] = useState(event.budget_total || 0);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let cancelled = false;
    eventsApi.candidates(eventId).then((d) => {
      if (!cancelled) { setCandidates(d.candidates || []); setLoading(false); }
    });
    return () => { cancelled = true; };
  }, [eventId]);

  // A restaurant candidate with a menu attached prices as
  // menuPricePerGuest × guests, never Listing.Price (brief section 4) —
  // candidateEstimate falls back to Listing.Price for every other
  // candidate, so this line's own behavior is unchanged for them.
  const selected = candidates.filter((c) => c.status === 'selected');
  const spent = selected.reduce((sum, c) => sum + candidateEstimate(c, event), 0);
  const remaining = (event.budget_total || 0) - spent;
  const overBy = remaining < 0 ? -remaining : 0;
  const pct = event.budget_total > 0 ? Math.min(100, (spent / event.budget_total) * 100) : (spent > 0 ? 100 : 0);

  const byCategory = new Map();
  for (const c of selected) {
    const label = (lang === 'kz' ? c.listing?.category?.name_kz : c.listing?.category?.name_ru) || (lang === 'kz' ? 'Басқа' : 'Другое');
    byCategory.set(label, (byCategory.get(label) || 0) + candidateEstimate(c, event));
  }
  const maxCategoryAmount = Math.max(1, ...Array.from(byCategory.values()));

  async function handleSaveBudget(e) {
    e.preventDefault();
    setSaving(true);
    try {
      await refreshSaveBudget();
      setEditing(false);
    } catch (err) {
      alert(err.message);
    } finally {
      setSaving(false);
    }
  }

  async function refreshSaveBudget() {
    await eventsApi.update(eventId, {
      title: event.title,
      type: event.type,
      event_date: event.event_date ? event.event_date.slice(0, 10) : null,
      city: event.city,
      guests: event.guests,
      budget_total: Number(budgetInput) || 0,
      comment: event.comment,
    });
    await refreshEvent();
    await refreshSummary();
  }

  return (
    <div>
      <h2 className="ws-section-title"><T ru="Бюджет" kz="Бюджет" /></h2>

      <div className="ws-budget-summary">
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Общий бюджет" kz="Жалпы бюджет" /></div>
          <div className="ws-stat__value">{formatPrice(event.budget_total || 0)}</div>
        </div>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Выбрано услуг" kz="Таңдалған қызметтер" /></div>
          <div className="ws-stat__value">{formatPrice(spent)}</div>
        </div>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Осталось" kz="Қалды" /></div>
          <div className="ws-stat__value">{formatPrice(Math.max(0, remaining))}</div>
        </div>
      </div>

      <div className="ws-progress" style={{ marginBottom: 10 }}>
        <div className={`ws-progress__fill${overBy > 0 ? ' ws-progress__fill--over' : ''}`} style={{ width: `${pct}%` }} />
      </div>
      {overBy > 0 && (
        <div className="ws-budget-warning">
          <T ru={`Бюджет превышен на ${formatPrice(overBy)}`} kz={`Бюджет ${formatPrice(overBy)} асып кетті`} />
        </div>
      )}

      {canEdit && (
        editing ? (
          <form className="contacts__form" onSubmit={handleSaveBudget} style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 12, margin: '22px 0' }}>
            <label style={{ flex: 1 }}>
              <span><T ru="Новый бюджет, ₸" kz="Жаңа бюджет, ₸" /></span>
              <input type="number" min="0" value={budgetInput} onChange={(e) => setBudgetInput(e.target.value)} />
            </label>
            <button type="submit" className="btn btn--gold" disabled={saving}><T ru="Сохранить" kz="Сақтау" /></button>
            <button type="button" className="btn btn--outline" onClick={() => setEditing(false)}><T ru="Отмена" kz="Бас тарту" /></button>
          </form>
        ) : (
          <button type="button" className="admin-table__link" style={{ display: 'inline-block', margin: '18px 0 30px' }} onClick={() => setEditing(true)}>
            <T ru="Изменить бюджет" kz="Бюджетті өзгерту" />
          </button>
        )
      )}

      <h3 className="ws-section-title" style={{ fontSize: 16, marginTop: 30 }}><T ru="По категориям" kz="Санаттар бойынша" /></h3>

      {loading && <div className="ws-skeleton" style={{ height: 140 }} />}
      {!loading && byCategory.size === 0 && (
        <p className="ws-empty__text" style={{ textAlign: 'left' }}>
          <T ru="Пока ничего не выбрано — бюджет пуст." kz="Әзірге ештеңе таңдалмады — бюджет бос." />
        </p>
      )}
      {!loading && Array.from(byCategory.entries()).map(([label, amount]) => (
        <div className="ws-budget-row" key={label}>
          <span>{label}</span>
          <div className="ws-budget-row__bar">
            <div className="ws-progress"><div className="ws-progress__fill" style={{ width: `${(amount / maxCategoryAmount) * 100}%` }} /></div>
          </div>
          <span style={{ fontWeight: 700, color: 'var(--gold-light)' }}>{formatPrice(amount)}</span>
        </div>
      ))}

      {/* Brief section 4's own exact example — the formula itself, for
          each selected restaurant/menu candidate, not just the lumped
          category sum above. */}
      {!loading && selected.filter((c) => c.menu_id).length > 0 && (
        <>
          <h3 className="ws-section-title" style={{ fontSize: 16, marginTop: 30 }}><T ru="Рестораны" kz="Мейрамханалар" /></h3>
          {selected.filter((c) => c.menu_id).map((c) => {
            const guests = c.guests || event.guests || 0;
            return (
              <div className="ws-budget-restaurant-row" key={c.id}>
                <div className="ws-budget-restaurant-row__name">{c.listing?.name_ru}{c.menu_name ? ` — ${c.menu_name}` : ''}</div>
                {guests > 0 && c.menu_price_per_guest > 0 && (
                  <div className="ws-budget-restaurant-row__formula">
                    {formatPrice(c.menu_price_per_guest)} × {guests} <T ru="гостей" kz="қонақ" />
                  </div>
                )}
                <div className="ws-budget-restaurant-row__total">{formatPrice(candidateEstimate(c, event))}</div>
              </div>
            );
          })}
        </>
      )}
    </div>
  );
}
