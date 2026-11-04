'use client';

import { useCallback, useEffect, useState } from 'react';
import { adminApi } from '@/lib/adminApi';
import { formatDateTime } from '@/lib/eventHelpers';

const STATUS_LABELS = {
  pending: 'Ожидает проверки',
  approved: 'Код выдан',
  rejected: 'Отклонён',
  used: 'Код использован',
  expired: 'Истёк',
};

const STATUS_CLASS = { approved: 'paid', used: 'paid' };

const ERRORS = {
  self_approval_forbidden: 'Нельзя выдать код для своего аккаунта: это должен сделать другой администратор.',
  invalid_status: 'Запрос уже обработан или истёк. Обновите список.',
  not_allowed: 'Аккаунт не активен, код выдать нельзя.',
  not_found: 'Запрос не найден.',
};

const errorText = (err) => ERRORS[err.message] || 'Не удалось выполнить действие. Попробуйте ещё раз.';

/** Shows a just-issued temporary code. It lives only in this page's state:
 * the backend keeps its hash and can't show it again. */
function IssuedCode({ issued, onHide }) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(issued.code);
      setCopied(true);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="recovery-code recovery-request__issued">
      <p className="recovery-code__title">Временный код для {issued.name}</p>
      <code className="recovery-code__value" data-testid="temp-code">{issued.code}</code>
      <p className="recovery-code__warning">
        Показывается только сейчас. Действует до {formatDateTime(issued.expiresAt, 'ru')}, один раз.
        Передайте его лично владельцу аккаунта.
      </p>
      <div className="recovery-request__actions">
        <button type="button" className="btn btn--outline" onClick={handleCopy}>
          {copied ? 'Скопировано' : 'Скопировать'}
        </button>
        <button type="button" className="btn btn--outline" onClick={onHide}>Скрыть код</button>
      </div>
    </div>
  );
}

function RequestCard({ request, busy, onApprove, onReject }) {
  const [note, setNote] = useState('');
  const user = request.user;
  const open = request.status === 'pending' || request.status === 'approved';
  const isReissue = request.status === 'approved';
  const name = user?.name || `Пользователь #${request.user_id}`;

  return (
    <div className={`booking-card recovery-request booking-card--${STATUS_CLASS[request.status] || 'pending'}`}>
      <div className="booking-card__head">
        <div>
          <p className="booking-card__customer">{name}</p>
          <span className="booking-card__phone">{user?.email || '—'} · {user?.phone || 'телефон не указан'}</span>
          {user?.role === 'admin' && <p className="recovery-request__warning">Это аккаунт администратора</p>}
        </div>
        <div className="booking-card__meta">
          <span className="booking-card__date">{formatDateTime(request.requested_at, 'ru')}</span>
          <span className={`my-booking__status my-booking__status--${STATUS_CLASS[request.status] || 'pending'}`}>
            {STATUS_LABELS[request.status] || request.status}
          </span>
        </div>
      </div>
      {request.admin_note && <p className="recovery-request__note">Заметка: {request.admin_note}</p>}
      {open && (
        <>
          <input
            className="admin-filters__search recovery-request__input"
            type="text"
            maxLength={500}
            value={note}
            onChange={(e) => setNote(e.target.value)}
            placeholder="Как подтверждена личность (необязательно)"
            aria-label="Заметка"
          />
          <div className="recovery-request__actions">
            <button type="button" className="btn btn--gold" disabled={busy} onClick={() => onApprove(request, note, name)}>
              {isReissue ? 'Выдать новый код' : 'Подтвердить и выдать код'}
            </button>
            <button type="button" className="btn btn--outline" disabled={busy} onClick={() => onReject(request, note, name)}>
              {isReissue ? 'Отозвать код' : 'Отклонить'}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

export default function AdminRecoveryRequestsPage() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [statusFilter, setStatusFilter] = useState('pending');
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState(null);
  const [issued, setIssued] = useState(null);

  const load = useCallback((status) => {
    return adminApi.recoveryRequests(status)
      .then((d) => setRequests(d.requests || []))
      .catch(() => setError('Не удалось загрузить запросы. Попробуйте ещё раз.'))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    load(statusFilter);
  }, [load, statusFilter]);

  async function act(request, action) {
    setError('');
    setBusyId(request.id);
    try {
      await action();
      await load(statusFilter);
    } catch (err) {
      setError(errorText(err));
    } finally {
      setBusyId(null);
    }
  }

  function handleApprove(request, note, name) {
    const question = request.status === 'approved'
      ? `Выдать новый код для «${name}»? Прежний перестанет действовать.`
      : `Вы убедились, что запрос подал владелец аккаунта «${name}»? Код позволит сменить пароль.`;
    if (!window.confirm(question)) return;
    act(request, async () => {
      const res = await adminApi.approveRecoveryRequest(request.id, note);
      setIssued({ code: res.temp_code, expiresAt: res.expires_at, name });
    });
  }

  function handleReject(request, note, name) {
    const question = request.status === 'approved'
      ? `Отозвать выданный код для «${name}»?`
      : `Отклонить запрос от «${name}»?`;
    if (!window.confirm(question)) return;
    act(request, async () => {
      await adminApi.rejectRecoveryRequest(request.id, note);
      setIssued(null);
    });
  }

  return (
    <div>
      <h1 className="admin-page-title">Восстановление аккаунтов</h1>
      <p className="recovery-code__warning recovery-request__intro">
        Перед выдачей кода свяжитесь с человеком по контактам из аккаунта и убедитесь, что это его владелец.
      </p>

      <div className="admin-filters">
        <select
          value={statusFilter}
          onChange={(e) => {
            setLoading(true);
            setStatusFilter(e.target.value);
          }}
          aria-label="Статус"
        >
          <option value="all">Все статусы</option>
          {Object.entries(STATUS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
      </div>

      {error && <p className="auth-card__error">{error}</p>}
      {issued && <IssuedCode issued={issued} onHide={() => setIssued(null)} />}

      {loading && <p className="admin-table__empty">Загрузка…</p>}
      {!loading && requests.length === 0 && <p className="admin-table__empty">Запросов нет</p>}

      <div className="booking-list">
        {requests.map((r) => (
          <RequestCard key={r.id} request={r} busy={busyId !== null} onApprove={handleApprove} onReject={handleReject} />
        ))}
      </div>
    </div>
  );
}
