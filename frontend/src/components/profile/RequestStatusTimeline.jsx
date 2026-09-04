'use client';

import { T } from '@/context/AppProviders';

// The happy-path sequence — rejected/cancelled are terminal exits rendered
// separately below, not steps on this line.
const STEPS = [
  { key: 'draft', ru: 'Черновик', kz: 'Жоба', en: 'Draft' },
  { key: 'submitted', ru: 'Отправлена', kz: 'Жіберілді', en: 'Submitted' },
  { key: 'in_review', ru: 'На рассмотрении', kz: 'Қаралуда', en: 'In review' },
  { key: 'changes_requested', ru: 'Требуются изменения', kz: 'Өзгеріс қажет', en: 'Changes requested' },
  { key: 'approved', ru: 'Подтверждена', kz: 'Расталды', en: 'Approved' },
];

/** A real progress component for the request's status, not just a text
 * label — a horizontal step line on desktop and tablet, same markup wraps
 * on narrow phones. Rejected/cancelled render as a separate terminal
 * banner instead of a 6th step, since they end the flow rather than
 * continuing it. */
export default function RequestStatusTimeline({ status }) {
  if (status === 'rejected' || status === 'cancelled') {
    return (
      <div className="ws-status-terminal">
        <span>{status === 'rejected' ? '✕' : '⊘'}</span>
        <span>
          {status === 'rejected'
            ? <T ru="Заявка отклонена" kz="Өтінім қабылданбады" en="Request rejected" />
            : <T ru="Заявка отменена" kz="Өтінім бас тартылды" en="Request cancelled" />}
        </span>
      </div>
    );
  }

  const currentIndex = STEPS.findIndex((s) => s.key === status);

  return (
    <div className="ws-status-timeline">
      {STEPS.map((step, i) => {
        const state = i < currentIndex ? 'is-done' : i === currentIndex ? 'is-active' : '';
        return (
          <div className={`ws-status-step ${state}`} key={step.key}>
            <span className="ws-status-step__line" />
            <span className="ws-status-step__dot">{i < currentIndex ? '✓' : i + 1}</span>
            <span className="ws-status-step__label"><T ru={step.ru} kz={step.kz} en={step.en} /></span>
          </div>
        );
      })}
    </div>
  );
}
