'use client';

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { T, useLang } from '@/context/AppProviders';
import { useEventWorkspace } from '@/context/EventWorkspaceContext';
import { eventsApi } from '@/lib/eventsApi';
import { initials, roleLabel } from '@/lib/eventHelpers';

export default function EventMembersPage() {
  const { eventId, isOwner } = useEventWorkspace();
  const { user } = useAuth();
  const { lang } = useLang();
  const [members, setMembers] = useState([]);
  const [invitations, setInvitations] = useState([]);
  const [loading, setLoading] = useState(true);
  const [inviteRole, setInviteRole] = useState('editor');
  const [inviteEmail, setInviteEmail] = useState('');
  const [creating, setCreating] = useState(false);
  const [copiedId, setCopiedId] = useState(null);
  const [emailedId, setEmailedId] = useState(null);

  const load = useCallback(async () => {
    const tasks = [eventsApi.members(eventId)];
    if (isOwner) tasks.push(eventsApi.listInvitations(eventId));
    const results = await Promise.all(tasks);
    setMembers(results[0].members || []);
    if (isOwner) setInvitations(results[1]?.invitations || []);
    setLoading(false);
  }, [eventId, isOwner]);

  useEffect(() => { load(); }, [load]);

  function inviteUrl(token) {
    return typeof window !== 'undefined' ? `${window.location.origin}/invite/${token}` : `/invite/${token}`;
  }

  async function handleCreateInvite(e) {
    e.preventDefault();
    setCreating(true);
    try {
      const { invitation } = await eventsApi.createInvitation(eventId, inviteRole, inviteEmail.trim());
      setInviteEmail('');
      if (invitation?.invitee_email) {
        setEmailedId(invitation.id);
        setTimeout(() => setEmailedId(null), 4000);
      }
      await load();
    } catch (err) {
      alert(err.message);
    } finally {
      setCreating(false);
    }
  }

  function copyLink(inv) {
    navigator.clipboard?.writeText(inviteUrl(inv.token));
    setCopiedId(inv.id);
    setTimeout(() => setCopiedId(null), 1800);
  }

  function whatsappShareUrl(inv) {
    const link = inviteUrl(inv.token);
    const text = lang === 'kz'
      ? `Тойды бірге жоспарлауға көмектесуге шақырамын. Ашу: ${link}`
      : `Приглашаю помочь выбрать услуги для нашего мероприятия. Открыть планирование → ${link}`;
    return `https://wa.me/?text=${encodeURIComponent(text)}`;
  }

  function mailShareUrl(inv) {
    const subject = lang === 'kz' ? 'MEREYTOI шақыруы' : 'Приглашение MEREYTOI';
    return `mailto:?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(inviteUrl(inv.token))}`;
  }

  async function handleChangeRole(userId, role) {
    try {
      await eventsApi.changeRole(eventId, userId, role);
      await load();
    } catch (err) {
      alert(err.message);
    }
  }

  async function handleRemove(userId) {
    const confirmText = lang === 'kz' ? 'Қатысушыны алып тастау керек пе?' : 'Удалить участника?';
    if (!window.confirm(confirmText)) return;
    try {
      await eventsApi.removeMember(eventId, userId);
      await load();
    } catch (err) {
      alert(err.message);
    }
  }

  async function handleRevoke(invId) {
    try {
      await eventsApi.revokeInvitation(eventId, invId);
      await load();
    } catch (err) {
      alert(err.message);
    }
  }

  const activeInvitations = invitations.filter((i) => !i.revoked);

  return (
    <div>
      <h2 className="ws-section-title"><T ru="Участники" kz="Қатысушылар" /></h2>

      {loading && <div className="ws-skeleton" style={{ height: 140 }} />}

      {!loading && members.map((m) => (
        <div className="ws-member-row" key={m.id}>
          <div className="ws-avatar">{initials(m.user?.name)}</div>
          <div>
            <div className="ws-member-row__name">
              {m.user?.name} {m.user_id === user?.id && <span style={{ color: 'var(--text-muted)', fontWeight: 400 }}>(<T ru="вы" kz="сіз" />)</span>}
            </div>
            <div className="ws-member-row__email">{m.user?.email}</div>
          </div>
          <div className="ws-member-row__actions">
            {isOwner && m.role !== 'owner' ? (
              <>
                <select className="ws-status-select" value={m.role} onChange={(e) => handleChangeRole(m.user_id, e.target.value)}>
                  <option value="editor">{roleLabel('editor', lang)}</option>
                  <option value="viewer">{roleLabel('viewer', lang)}</option>
                </select>
                <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleRemove(m.user_id)}>
                  <T ru="Удалить" kz="Жою" />
                </button>
              </>
            ) : (
              <span className="ws-chip ws-chip--gold">{roleLabel(m.role, lang)}</span>
            )}
          </div>
        </div>
      ))}

      {!loading && members.length <= 1 && (
        <div className="ws-empty" style={{ marginTop: 24 }}>
          <span className="ws-empty__icon">🤝</span>
          <h3 className="ws-empty__title"><T ru="Организовывать вместе проще" kz="Бірге ұйымдастыру оңай" /></h3>
          <p className="ws-empty__text"><T ru="Пригласите близких помочь вам с выбором." kz="Таңдауға көмектесу үшін жақындарыңызды шақырыңыз." /></p>
        </div>
      )}

      {isOwner && (
        <>
          <h3 className="ws-section-title" style={{ fontSize: 16, marginTop: 36 }}><T ru="Пригласить" kz="Шақыру" /></h3>
          <form className="contacts__form" onSubmit={handleCreateInvite} style={{ flexDirection: 'row', alignItems: 'flex-end', gap: 12, flexWrap: 'wrap' }}>
            <label style={{ flex: '1 1 260px' }}>
              <span><T ru="Роль приглашённого" kz="Шақырылған рөлі" /></span>
              <select value={inviteRole} onChange={(e) => setInviteRole(e.target.value)}>
                <option value="editor">{lang === 'kz' ? 'Қатысушы — таңдайды, дауыс береді, пікір қалдырады' : 'Участник — выбирает, голосует, комментирует'}</option>
                <option value="viewer">{lang === 'kz' ? 'Бақылаушы — тек көру және дауыс беру' : 'Наблюдатель — только просмотр и голосование'}</option>
              </select>
            </label>
            <label style={{ flex: '1 1 220px' }}>
              <span><T ru="Email (необязательно)" kz="Email (міндетті емес)" en="Email (optional)" /></span>
              <input
                type="email"
                value={inviteEmail}
                onChange={(e) => setInviteEmail(e.target.value)}
                placeholder={lang === 'kz' ? 'жақынныңыз@мысал.kz' : 'близкий@пример.kz'}
              />
            </label>
            <button type="submit" className="btn btn--gold" disabled={creating}>+ <T ru="Создать ссылку" kz="Сілтеме жасау" /></button>
          </form>
          {inviteEmail.trim() && (
            <p className="ws-empty__text" style={{ textAlign: 'left', marginTop: 8, fontSize: 13 }}>
              <T ru="Ссылка будет также отправлена на этот email." kz="Сілтеме осы email-ге де жіберіледі." en="The link will also be emailed to this address." />
            </p>
          )}

          {activeInvitations.length === 0 && !loading && (
            <p className="ws-empty__text" style={{ textAlign: 'left', marginTop: 16 }}>
              <T ru="Активных приглашений пока нет." kz="Әзірге белсенді шақырулар жоқ." />
            </p>
          )}

          {activeInvitations.map((inv) => (
            <div key={inv.id} style={{ marginTop: 18 }}>
              <div className="ws-invite-link-box">
                <input readOnly value={inviteUrl(inv.token)} onFocus={(e) => e.target.select()} />
                <button type="button" className="admin-table__link" onClick={() => copyLink(inv)}>
                  {copiedId === inv.id ? <T ru="Скопировано!" kz="Көшірілді!" /> : <T ru="Копировать" kz="Көшіру" />}
                </button>
              </div>
              <div className="ws-invite-share">
                <span className="ws-chip ws-chip--outline">{roleLabel(inv.role, lang)}</span>
                {inv.invitee_email && (
                  <span className="ws-chip ws-chip--gold" title={inv.invitee_email}>
                    {emailedId === inv.id
                      ? <T ru="✉️ Отправлено!" kz="✉️ Жіберілді!" en="✉️ Sent!" />
                      : <T ru={`✉️ ${inv.invitee_email}`} kz={`✉️ ${inv.invitee_email}`} en={`✉️ ${inv.invitee_email}`} />}
                  </span>
                )}
                <a className="btn btn--outline" style={{ padding: '8px 16px', fontSize: 13 }} href={whatsappShareUrl(inv)} target="_blank" rel="noopener noreferrer">
                  WhatsApp
                </a>
                <a className="btn btn--outline" style={{ padding: '8px 16px', fontSize: 13 }} href={mailShareUrl(inv)}>
                  Email
                </a>
                <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleRevoke(inv.id)}>
                  <T ru="Отозвать" kz="Кері қайтару" />
                </button>
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  );
}
