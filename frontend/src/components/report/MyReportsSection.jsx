'use client';

import { useEffect, useState } from 'react';
import { T } from '@/context/AppProviders';
import { reportsApi } from '@/lib/reportsApi';
import { ReasonLabel, StatusLabel, TargetLabel } from './reportLabels';

function formatDate(v) {
  if (!v) return '';
  return new Date(v).toLocaleDateString('ru-RU');
}

// «Мои жалобы» in the profile: what, why, status and dates — never who
// reviewed it or the administrators' notes.
export default function MyReportsSection() {
  const [reports, setReports] = useState(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let alive = true;
    reportsApi.mine()
      .then((d) => { if (alive) setReports(d.reports || []); })
      .catch(() => { if (alive) setFailed(true); });
    return () => { alive = false; };
  }, []);

  return (
    <div id="my-reports" style={{ marginTop: 32 }}>
      <h2 className="admin-section-title" style={{ marginTop: 0 }}>
        <T ru="Мои жалобы" kz="Менің шағымдарым" en="My reports" />
      </h2>
      {failed && <p className="admin-table__empty"><T ru="Не удалось загрузить жалобы" kz="Шағымдарды жүктеу мүмкін болмады" en="Couldn't load your reports" /></p>}
      {!failed && reports === null && <p className="admin-table__empty">…</p>}
      {reports && reports.length === 0 && (
        <p className="admin-table__empty">
          <T ru="Вы ещё не отправляли жалоб." kz="Сіз әлі шағым жібермегенсіз." en="You haven't sent any reports yet." />
        </p>
      )}
      {reports && reports.length > 0 && (
        <>
          <div className="my-reports">
            {reports.map((r) => (
              <div className="my-report" key={r.id} data-testid={`my-report-${r.id}`}>
                <div className="my-report__head">
                  <span className="my-report__title">{r.target_title || <TargetLabel code={r.target_type} />}</span>
                  <span className={`my-report__status my-report__status--${r.status}`}><StatusLabel code={r.status} /></span>
                </div>
                <div className="my-report__meta">
                  <TargetLabel code={r.target_type} /> · <ReasonLabel code={r.reason} />
                </div>
                <div className="my-report__meta">
                  <T ru="Отправлена" kz="Жіберілді" en="Sent" /> {formatDate(r.created_at)}
                  {r.resolved_at && <> · <T ru="решение" kz="шешім" en="decided" /> {formatDate(r.resolved_at)}</>}
                </div>
              </div>
            ))}
          </div>
          <p className="admin-table__empty" style={{ textAlign: 'left' }}>
            <T ru="Решение принимает администратор. Подробности проверки не раскрываются." kz="Шешімді әкімші қабылдайды. Тексеру мәліметтері ашылмайды." en="An administrator decides. Review details aren't disclosed." />
          </p>
        </>
      )}
    </div>
  );
}
