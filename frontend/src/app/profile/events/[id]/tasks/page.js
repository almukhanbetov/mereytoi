'use client';

import { useCallback, useEffect, useState } from 'react';
import { T, useLang } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { formatEventDate } from '@/lib/eventHelpers';

export default function EventTasksPage() {
  const { eventId, canEdit } = useEventWorkspace();
  const { lang } = useLang();
  const [tasks, setTasks] = useState([]);
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [title, setTitle] = useState('');
  const [assignee, setAssignee] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [adding, setAdding] = useState(false);

  const load = useCallback(async () => {
    const [t, m] = await Promise.all([eventsApi.tasks(eventId), eventsApi.members(eventId)]);
    setTasks(t.tasks || []);
    setMembers(m.members || []);
    setLoading(false);
  }, [eventId]);

  useEffect(() => { load(); }, [load]);

  async function handleAdd(e) {
    e.preventDefault();
    if (!title.trim() || adding) return;
    setAdding(true);
    try {
      await eventsApi.createTask(eventId, { title: title.trim(), assignee_id: assignee ? Number(assignee) : null, due_date: dueDate || null });
      setTitle(''); setAssignee(''); setDueDate('');
      await load();
    } catch (err) {
      alert(err.message);
    } finally {
      setAdding(false);
    }
  }

  async function toggleDone(task) {
    const next = task.status === 'done' ? 'todo' : 'done';
    setTasks((prev) => prev.map((t) => (t.id === task.id ? { ...t, status: next } : t)));
    try {
      await eventsApi.updateTask(eventId, task.id, { status: next });
    } catch {
      load();
    }
  }

  async function handleDelete(id) {
    const confirmText = lang === 'kz' ? 'Тапсырманы жоясыз ба?' : 'Удалить задачу?';
    if (!window.confirm(confirmText)) return;
    try {
      await eventsApi.deleteTask(eventId, id);
      setTasks((prev) => prev.filter((t) => t.id !== id));
    } catch (err) {
      alert(err.message);
    }
  }

  return (
    <div>
      <h2 className="ws-section-title"><T ru="Задачи" kz="Тапсырмалар" /></h2>

      {loading && <div className="ws-skeleton" style={{ height: 160 }} />}

      {!loading && tasks.length === 0 && (
        <p className="ws-empty__text" style={{ textAlign: 'left', marginBottom: 24 }}>
          <T ru="Задач пока нет." kz="Әзірге тапсырма жоқ." />
        </p>
      )}

      {!loading && tasks.length > 0 && (
        <div style={{ marginBottom: 28 }}>
          {tasks.map((t) => (
            <div className={`ws-task-row${t.status === 'done' ? ' is-done' : ''}`} key={t.id}>
              <button
                type="button"
                className={`ws-task-check${t.status === 'done' ? ' is-done' : ''}`}
                onClick={() => toggleDone(t)}
                aria-pressed={t.status === 'done'}
                aria-label={t.status === 'done'
                  ? (lang === 'kz' ? 'Орындалды деп белгіленген, алып тастау' : 'Отмечено выполненным, снять отметку')
                  : (lang === 'kz' ? 'Орындалды деп белгілеу' : 'Отметить как выполненное')}
              >
                {t.status === 'done' ? '✓' : ''}
              </button>
              <span className="ws-task-row__title">{t.title}</span>
              <div className="ws-task-row__meta">
                {t.assignee && <span className="ws-chip ws-chip--outline">{t.assignee.name}</span>}
                {t.due_date && <span className="ws-chip">{formatEventDate(t.due_date, lang)}</span>}
                {canEdit && (
                  <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(t.id)}>✕</button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {canEdit && (
        <form className="contacts__form" onSubmit={handleAdd} style={{ flexDirection: 'row', flexWrap: 'wrap', alignItems: 'flex-end', gap: 12 }}>
          <label style={{ flex: '2 1 220px' }}>
            <span><T ru="Новая задача" kz="Жаңа тапсырма" /></span>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={lang === 'kz' ? 'Мысалы, «Мейрамханаға қоңырау шалу»' : 'Например, «Позвонить ресторану»'} />
          </label>
          <label style={{ flex: '1 1 160px' }}>
            <span><T ru="Ответственный" kz="Жауапты" /></span>
            <select value={assignee} onChange={(e) => setAssignee(e.target.value)}>
              <option value="">—</option>
              {members.map((m) => <option key={m.user_id} value={m.user_id}>{m.user?.name}</option>)}
            </select>
          </label>
          <label style={{ flex: '1 1 150px' }}>
            <span><T ru="Срок" kz="Мерзімі" /></span>
            <input type="date" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </label>
          <button type="submit" className="btn btn--gold" disabled={adding || !title.trim()}>
            + <T ru="Добавить" kz="Қосу" />
          </button>
        </form>
      )}
    </div>
  );
}
