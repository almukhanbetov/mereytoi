'use client';

import { useCallback, useEffect, useState } from 'react';
import { T, useLang } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { fetchCategoriesClient } from '@/lib/catalogApi';
import { formatPrice } from '@/lib/format';
import { formatEventDate, formatDateTime } from '@/lib/eventHelpers';
import RequestStatusTimeline from '@/components/profile/RequestStatusTimeline';
import InlineNotice from '@/components/profile/InlineNotice';
import WsModal from '@/components/profile/WsModal';

const nameOf = (obj, lang) => (obj ? (lang === 'kz' ? obj.name_kz : obj.name_ru) || obj.name_ru : '');

export default function EventRequestPage() {
  const { eventId, event, isOwner, refreshSummary } = useEventWorkspace();
  const { lang } = useLang();

  const [loading, setLoading] = useState(true);
  const [request, setRequest] = useState(null);
  const [revisions, setRevisions] = useState([]);
  const [candidates, setCandidates] = useState([]);
  const [categories, setCategories] = useState([]);

  const [comment, setComment] = useState('');
  const [saving, setSaving] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [notice, setNotice] = useState(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [cancelOpen, setCancelOpen] = useState(false);

  const load = useCallback(async () => {
    const [reqData, candData, cats] = await Promise.all([
      eventsApi.getRequest(eventId),
      eventsApi.candidates(eventId),
      fetchCategoriesClient(),
    ]);
    setRequest(reqData.request);
    setRevisions(reqData.revisions || []);
    setCandidates(candData.candidates || []);
    setCategories(cats);
    setComment(reqData.request.organizer_comment || '');
    setLoading(false);
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  if (loading || !request) {
    return <div className="ws-skeleton" style={{ height: 320 }} />;
  }

  const selected = candidates.filter((c) => c.status === 'selected');
  const total = selected.reduce((sum, c) => sum + (c.listing?.price || 0), 0);
  const selectedCategoryIds = new Set(selected.map((c) => c.listing?.category_id).filter(Boolean));
  const missingCategories = categories.filter((cat) => !selectedCategoryIds.has(cat.id));
  const editable = request.status === 'draft' || request.status === 'changes_requested';
  const canCancel = isOwner && ['draft', 'submitted', 'in_review', 'changes_requested'].includes(request.status);

  async function handleSaveComment() {
    setSaving(true);
    setNotice(null);
    try {
      const { request: updated } = await eventsApi.updateRequest(eventId, comment);
      setRequest(updated);
      setNotice({ type: 'success', text: <T ru="Комментарий сохранён" kz="Пікір сақталды" en="Comment saved" /> });
    } catch (err) {
      setNotice({ type: 'error', text: err.message });
    } finally {
      setSaving(false);
    }
  }

  async function handleSubmit() {
    setSubmitting(true);
    try {
      const { request: updated } = await eventsApi.submitRequest(eventId);
      setRequest(updated);
      setConfirmOpen(false);
      setNotice({ type: 'success', text: <T ru="Заявка отправлена в MEREYTOI" kz="Өтінім MEREYTOI-ға жіберілді" en="Request sent to MEREYTOI" /> });
      await load();
      refreshSummary();
    } catch (err) {
      setNotice({ type: 'error', text: err.message });
    } finally {
      setSubmitting(false);
    }
  }

  async function handleCancel() {
    setSubmitting(true);
    try {
      const { request: updated } = await eventsApi.cancelRequest(eventId);
      setRequest(updated);
      setCancelOpen(false);
    } catch (err) {
      setNotice({ type: 'error', text: err.message });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div>
      <h2 className="ws-section-title"><T ru="Заявка" kz="Өтінім" en="Request" /></h2>

      <RequestStatusTimeline status={request.status} />

      {request.manager_comment && request.status !== 'draft' && request.status !== 'submitted' && (
        <div className="ws-manager-note">
          <div className="ws-manager-note__label"><T ru="Комментарий менеджера" kz="Менеджер пікірі" en="Manager comment" /></div>
          <div className="ws-manager-note__text">{request.manager_comment}</div>
        </div>
      )}

      {request.status === 'approved' && (
        <div className="ws-status-terminal ws-status-terminal--approved">
          <span>✓</span>
          <span>
            <T ru="Заявка подтверждена" kz="Өтінім расталды" en="Request approved" />
            {request.booking_id ? ` · № ${request.booking_id}` : ''}
          </span>
        </div>
      )}

      <div className="ws-stats" style={{ marginBottom: 26 }}>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Дата" kz="Күні" en="Date" /></div>
          <div className="ws-stat__value" style={{ fontSize: 15 }}>{formatEventDate(event.event_date, lang) || '—'}</div>
        </div>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Гостей" kz="Қонақтар" en="Guests" /></div>
          <div className="ws-stat__value" style={{ fontSize: 15 }}>{event.guests || '—'}</div>
        </div>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Город" kz="Қала" en="City" /></div>
          <div className="ws-stat__value" style={{ fontSize: 15 }}>{event.city || '—'}</div>
        </div>
        <div className="ws-stat">
          <div className="ws-stat__label"><T ru="Бюджет" kz="Бюджет" en="Budget" /></div>
          <div className="ws-stat__value" style={{ fontSize: 15 }}>{formatPrice(event.budget_total || 0)}</div>
        </div>
      </div>

      <h3 className="ws-section-title" style={{ fontSize: 16 }}><T ru="Выбранные услуги" kz="Таңдалған қызметтер" en="Selected services" /></h3>

      {selected.length === 0 && (
        <p className="ws-empty__text" style={{ textAlign: 'left' }}>
          <T ru="Пока ни одна услуга не выбрана." kz="Әзірге бір де бір қызмет таңдалмады." en="No services selected yet." />
        </p>
      )}

      <div style={{ marginBottom: 18 }}>
        {selected.map((c) => {
          const listing = c.listing || {};
          const votes = c.votes || {};
          return (
            <div className="ws-request-item" key={c.id}>
              <div className="ws-request-item__main">
                <span className="ws-request-item__name">{nameOf(listing, lang)}</span>
                <span className="ws-request-item__meta">
                  {nameOf(listing.category, lang)} · 👍 {votes.up || 0} · 🤔 {votes.maybe || 0} · 👎 {votes.down || 0} · 💬 {c.comment_count || 0}
                </span>
              </div>
              <span className="ws-request-item__price">{formatPrice(listing.price || 0)}</span>
            </div>
          );
        })}
      </div>

      {missingCategories.length > 0 && (
        <div className="ws-request-missing">
          ⚠ <T ru="Не выбрано:" kz="Таңдалмаған:" en="Not selected:" /> {missingCategories.map((c) => nameOf(c, lang)).join(', ')}
        </div>
      )}

      <div className="ws-request-total">
        <span><T ru="Ориентировочно" kz="Болжамды құны" en="Estimated total" /></span>
        <span>{formatPrice(total)}</span>
      </div>

      {isOwner && editable && (
        <>
          <label style={{ display: 'block', marginTop: 26 }}>
            <span style={{ display: 'block', fontSize: 13, color: 'var(--text-muted)', fontWeight: 600, marginBottom: 8 }}>
              <T ru="Комментарий организатора" kz="Ұйымдастырушы пікірі" en="Organizer comment" />
            </span>
            <textarea
              className="ws-composer-textarea"
              rows={3}
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              style={{ width: '100%', padding: '12px 16px', borderRadius: 14, border: '1px solid var(--border)', background: 'var(--input-bg)', color: 'var(--text)', fontFamily: 'inherit', fontSize: 14 }}
              placeholder={lang === 'kz' ? 'Мысалы, қалауларыңыз немесе ерекше жағдайлар' : lang === 'en' ? 'e.g. special requests or notes for the manager' : 'Например, пожелания или особые условия'}
            />
          </label>
          <button type="button" className="admin-table__link" style={{ marginTop: 8 }} onClick={handleSaveComment} disabled={saving}>
            {saving ? <T ru="Сохраняем…" kz="Сақталуда…" en="Saving…" /> : <T ru="Сохранить комментарий" kz="Пікірді сақтау" en="Save comment" />}
          </button>

          <InlineNotice type={notice?.type}>{notice?.text}</InlineNotice>

          <button
            type="button"
            className="btn btn--gold btn--block"
            style={{ marginTop: 20 }}
            onClick={() => setConfirmOpen(true)}
          >
            <T ru="Отправить заявку MEREYTOI" kz="MEREYTOI-ға өтінім жіберу" en="Send request to MEREYTOI" />
          </button>
        </>
      )}

      {!isOwner && (
        <p className="ws-empty__text" style={{ textAlign: 'left', marginTop: 20 }}>
          <T ru="Только организатор может отправить заявку." kz="Өтінімді тек ұйымдастырушы жібере алады." en="Only the organizer can submit the request." />
        </p>
      )}

      {!editable && isOwner && notice && <InlineNotice type={notice.type}>{notice.text}</InlineNotice>}

      {canCancel && (
        <button type="button" className="admin-table__link admin-table__link--danger" style={{ marginTop: 16, display: 'inline-block' }} onClick={() => setCancelOpen(true)}>
          <T ru="Отменить заявку" kz="Өтінімнен бас тарту" en="Cancel request" />
        </button>
      )}

      {revisions.length > 0 && (
        <>
          <h3 className="ws-section-title" style={{ fontSize: 16, marginTop: 36 }}><T ru="История версий" kz="Нұсқалар тарихы" en="Revision history" /></h3>
          {revisions.map((rev) => (
            <div className="ws-revision-card" key={rev.id}>
              <div className="ws-revision-card__head">
                <span className="ws-revision-card__title">
                  <T ru={`Версия ${rev.revision_number}`} kz={`${rev.revision_number}-нұсқа`} en={`Revision ${rev.revision_number}`} />
                </span>
                <span className="ws-revision-card__meta">{formatDateTime(rev.submitted_at, lang)}</span>
              </div>
              <div className="ws-revision-card__meta">{rev.submitted_by?.name} · {formatPrice(rev.total)}</div>
            </div>
          ))}
        </>
      )}

      {confirmOpen && (
        <WsModal title={<T ru="Отправить заявку MEREYTOI?" kz="MEREYTOI-ға жіберу керек пе?" en="Send request to MEREYTOI?" />} onClose={() => setConfirmOpen(false)}>
          <p style={{ color: 'var(--text-muted)', fontSize: 14, lineHeight: 1.6, marginBottom: 18 }}>
            <T
              ru="Мы зафиксируем текущий выбор услуг и стоимость. Дальнейшие изменения shortlist не повлияют на уже отправленную заявку."
              kz="Ағымдағы таңдауды және құнды бекітеміз. Кейінгі өзгерістер жіберілген өтінімге әсер етпейді."
              en="We'll freeze the current selection and price. Further shortlist changes won't affect what's already been submitted."
            />
          </p>
          <div className="ws-request-total" style={{ marginBottom: 18 }}>
            <span><T ru="Итого" kz="Барлығы" en="Total" /></span>
            <span>{formatPrice(total)}</span>
          </div>
          <div style={{ display: 'flex', gap: 12 }}>
            <button type="button" className="btn btn--outline" style={{ flex: 1 }} onClick={() => setConfirmOpen(false)} disabled={submitting}>
              <T ru="Отмена" kz="Бас тарту" en="Cancel" />
            </button>
            <button type="button" className="btn btn--gold" style={{ flex: 1 }} onClick={handleSubmit} disabled={submitting}>
              {submitting ? <T ru="Отправляем…" kz="Жіберілуде…" en="Sending…" /> : <T ru="Да, отправить" kz="Иә, жіберу" en="Yes, send it" />}
            </button>
          </div>
        </WsModal>
      )}

      {cancelOpen && (
        <WsModal title={<T ru="Отменить заявку?" kz="Өтінімнен бас тартасыз ба?" en="Cancel this request?" />} onClose={() => setCancelOpen(false)}>
          <p style={{ color: 'var(--text-muted)', fontSize: 14, lineHeight: 1.6, marginBottom: 18 }}>
            <T ru="Это действие можно будет отменить, подготовив заявку заново." kz="Бұл әрекетті кейін өтінімді қайта дайындап түзетуге болады." en="You can prepare and submit a new request afterward if you change your mind." />
          </p>
          <div style={{ display: 'flex', gap: 12 }}>
            <button type="button" className="btn btn--outline" style={{ flex: 1 }} onClick={() => setCancelOpen(false)} disabled={submitting}>
              <T ru="Назад" kz="Артқа" en="Back" />
            </button>
            <button type="button" className="btn btn--gold" style={{ flex: 1 }} onClick={handleCancel} disabled={submitting}>
              <T ru="Да, отменить" kz="Иә, бас тарту" en="Yes, cancel it" />
            </button>
          </div>
        </WsModal>
      )}
    </div>
  );
}
