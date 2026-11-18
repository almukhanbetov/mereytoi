'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { reportsApi } from '@/lib/reportsApi';
import { REPORT_REASONS, ReasonLabel, ReportError, TargetLabel } from './reportLabels';

// «Пожаловаться» — a quiet text button that opens the report dialog:
// reason + details → confirmation → result. Nothing is sent before
// «Отправить». A guest is offered to sign in instead. The person or business
// reported never learns who sent it.
export default function ReportButton({ targetType, targetId, targetName, className = '' }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        className={`report-link ${className}`}
        data-testid={`report-${targetType}-${targetId}`}
        onClick={() => setOpen(true)}
      >
        <svg viewBox="0 0 24 24" width="15" height="15" aria-hidden="true">
          <path d="M5 21V4h9l.6 2H20v10h-6.6l-.6-2H7v7H5z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
        </svg>
        <T ru="Пожаловаться" kz="Шағым жасау" en="Report" />
      </button>
      {open && (
        <ReportDialog
          targetType={targetType}
          targetId={targetId}
          targetName={targetName}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

function ReportDialog({ targetType, targetId, targetName, onClose }) {
  const { isAuthenticated } = useAuth();
  const [step, setStep] = useState('form'); // form | confirm | sent | duplicate
  const [reason, setReason] = useState('');
  const [details, setDetails] = useState('');
  const [tried, setTried] = useState(false);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');
  const dialogRef = useRef(null);

  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape' && !sending) onClose(); };
    window.addEventListener('keydown', onKey);
    dialogRef.current?.focus();
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, sending]);

  const trimmed = details.trim();
  const detailsInvalid = (reason === 'other' && [...trimmed].length < 5) || [...trimmed].length > 2000;

  const next = () => {
    setTried(true);
    if (!reason || detailsInvalid) return;
    setError('');
    setStep('confirm');
  };

  const send = async () => {
    if (sending) return;
    setSending(true);
    setError('');
    try {
      await reportsApi.create({ targetType, targetId, reason, details: trimmed });
      setStep('sent');
    } catch (err) {
      if (err.message === 'duplicate_report') setStep('duplicate');
      else setError(err.message || 'error');
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="report-overlay" onClick={() => !sending && onClose()}>
      <div
        className="report-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="report-title"
        tabIndex={-1}
        ref={dialogRef}
        onClick={(e) => e.stopPropagation()}
      >
        {!isAuthenticated ? (
          <>
            <h3 id="report-title" className="report-dialog__title">
              <T ru="Войдите, чтобы пожаловаться" kz="Шағым жасау үшін кіріңіз" en="Sign in to report" />
            </h3>
            <div className="report-dialog__actions">
              <Link href="/login" className="btn btn--gold"><T ru="Войти" kz="Кіру" en="Sign in" /></Link>
              <button type="button" className="btn btn--outline" onClick={onClose}><T ru="Отмена" kz="Болдырмау" en="Cancel" /></button>
            </div>
          </>
        ) : step === 'form' ? (
          <>
            <h3 id="report-title" className="report-dialog__title"><T ru="Пожаловаться" kz="Шағым жасау" en="Report" /></h3>
            <p className="report-dialog__target"><TargetLabel code={targetType} />: «{targetName}»</p>
            <fieldset className="report-reasons">
              <legend><T ru="Что не так?" kz="Не дұрыс емес?" en="What's wrong?" /></legend>
              {REPORT_REASONS.map((code) => (
                <label key={code} className={`report-reason${reason === code ? ' is-selected' : ''}`}>
                  <input type="radio" name="report-reason" value={code} checked={reason === code} onChange={() => setReason(code)} />
                  <ReasonLabel code={code} />
                </label>
              ))}
            </fieldset>
            {tried && !reason && (
              <p className="report-dialog__error"><T ru="Выберите причину" kz="Себепті таңдаңыз" en="Choose a reason" /></p>
            )}
            <label className="report-dialog__label" htmlFor="report-details">
              {reason === 'other'
                ? <T ru="Опишите проблему (обязательно)" kz="Мәселені сипаттаңыз (міндетті)" en="Describe the problem (required)" />
                : <T ru="Подробности (необязательно)" kz="Толығырақ (міндетті емес)" en="Details (optional)" />}
            </label>
            <textarea
              id="report-details"
              className="report-dialog__textarea"
              rows={3}
              maxLength={2000}
              value={details}
              onChange={(e) => setDetails(e.target.value)}
            />
            {tried && detailsInvalid && (
              <p className="report-dialog__error"><ReportError code="details_required" /></p>
            )}
            <div className="report-dialog__actions">
              <button type="button" className="btn btn--gold" onClick={next}><T ru="Далее" kz="Әрі қарай" en="Next" /></button>
              <button type="button" className="btn btn--outline" onClick={onClose}><T ru="Отмена" kz="Болдырмау" en="Cancel" /></button>
            </div>
          </>
        ) : step === 'confirm' ? (
          <>
            <h3 id="report-title" className="report-dialog__title"><T ru="Отправить жалобу?" kz="Шағымды жіберу керек пе?" en="Send the report?" /></h3>
            <div className="report-summary">
              <div><TargetLabel code={targetType} />: «{targetName}»</div>
              <div><b><T ru="Причина" kz="Себебі" en="Reason" />: <ReasonLabel code={reason} /></b></div>
              {trimmed && <div className="report-summary__details">{trimmed}</div>}
            </div>
            <p className="report-dialog__note">
              <T ru="Жалобу рассмотрит администратор. Тот, на кого вы жалуетесь, не узнает, кто её отправил." kz="Шағымды әкімші қарайды. Сіз шағымданған адам оны кім жібергенін білмейді." en="An administrator will review it. The person you're reporting won't know who sent it." />
            </p>
            {error && <p className="report-dialog__error"><ReportError code={error} /></p>}
            <div className="report-dialog__actions">
              <button type="button" className="btn btn--gold" disabled={sending} onClick={send}>
                {sending ? '…' : <T ru="Отправить" kz="Жіберу" en="Send" />}
              </button>
              <button type="button" className="btn btn--outline" disabled={sending} onClick={() => setStep('form')}><T ru="Назад" kz="Артқа" en="Back" /></button>
            </div>
          </>
        ) : (
          <>
            <h3 id="report-title" className="report-dialog__title">
              {step === 'sent'
                ? <T ru="Жалоба отправлена" kz="Шағым жіберілді" en="Report sent" />
                : <T ru="Жалоба уже отправлена" kz="Шағым бұрын жіберілген" en="Already reported" />}
            </h3>
            <p className="report-dialog__note">
              {step === 'sent'
                ? <T ru="Статус можно посмотреть в профиле, в разделе «Мои жалобы»." kz="Мәртебесін профильдегі «Менің шағымдарым» бөлімінен көруге болады." en="You can follow its status in your profile, under «My reports»." />
                : <ReportError code="duplicate_report" />}
            </p>
            <div className="report-dialog__actions">
              <button type="button" className="btn btn--gold" onClick={onClose}><T ru="Готово" kz="Дайын" en="Done" /></button>
              <Link href="/profile?tab=account#my-reports" className="btn btn--outline" onClick={onClose}><T ru="Мои жалобы" kz="Менің шағымдарым" en="My reports" /></Link>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
