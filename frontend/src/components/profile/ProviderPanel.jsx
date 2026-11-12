'use client';

import { useEffect, useState } from 'react';
import PromotionPanel from '@/components/profile/PromotionPanel';
import { T, useLang } from '@/context/AppProviders';
import { providerApi } from '@/lib/providerApi';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';
import { isRestaurantCategory } from '@/lib/restaurantCategory';
import ProviderServiceForm, { listingToPayload } from './ProviderServiceForm';
import ProviderRestaurantManager from './ProviderRestaurantManager';

const EMPTY_PROFILE = { display_name: '', city: '', description: '', experience_years: '', phone: '', whatsapp: '', telegram: '', avatar_url: '' };

// "Профиль → Стать услугодателем / Профиль услугодателя / Мои услуги / +
// Добавить услугу" — Этап 11, brief section 10. One self-contained panel
// dropped into profile/page.js's own tab system as a third tab; nothing
// here touches the Мои мероприятия/Аккаунт tabs' own state.
export default function ProviderPanel() {
  const { lang } = useLang();
  const [loading, setLoading] = useState(true);
  const [provider, setProvider] = useState(null); // null = not a provider yet
  const [loadFailed, setLoadFailed] = useState(false);
  const [listings, setListings] = useState([]);
  const [promoting, setPromoting] = useState(null); // listing shown in PromotionPanel
  const [categories, setCategories] = useState([]);

  const [editingProfile, setEditingProfile] = useState(false);
  const [profileForm, setProfileForm] = useState(EMPTY_PROFILE);
  const [profileError, setProfileError] = useState('');
  const [profileSaving, setProfileSaving] = useState(false);
  const [avatarUploading, setAvatarUploading] = useState(false);

  const [serviceForm, setServiceForm] = useState(null); // null | 'new' | listing object being edited
  const [managingId, setManagingId] = useState(null); // the restaurant being managed

  function loadMine() {
    providerApi
      .myListings()
      .then((d) => setListings(d.listings || []))
      .catch(() => {});
  }

  useEffect(() => {
    // `loading` already starts true (see useState above) — this effect
    // only ever runs once (deps: []), so there's nothing to reset it from.
    providerApi
      .me()
      .then((d) => {
        setProvider(d.provider);
        loadMine();
      })
      .catch((err) => {
        // Only a 404 means "not a provider yet": a network failure must not
        // offer an existing provider to sign up again.
        if (err.status !== 404) setLoadFailed(true);
      })
      .finally(() => setLoading(false));
    providerApi.categories().then((d) => setCategories(d.categories || [])).catch(() => {});
  }, []);

  function startBecomeProvider() {
    setProfileForm(EMPTY_PROFILE);
    setProfileError('');
    setEditingProfile(true);
  }

  function startEditProfile() {
    setProfileForm({
      display_name: provider.display_name || '',
      city: provider.city || '',
      description: provider.description || '',
      experience_years: provider.experience_years ?? '',
      phone: provider.phone || '',
      whatsapp: provider.whatsapp || '',
      telegram: provider.telegram || '',
      avatar_url: provider.avatar_url || '',
    });
    setProfileError('');
    setEditingProfile(true);
  }

  async function handleAvatarFile(e) {
    const files = e.target.files;
    if (!files || files.length === 0) return;
    setProfileError('');
    setAvatarUploading(true);
    try {
      const urls = await providerApi.uploadImages(files);
      if (urls[0]) setProfileForm((v) => ({ ...v, avatar_url: urls[0] }));
    } catch (err) {
      setProfileError(err.message || 'Не удалось загрузить фото');
    } finally {
      setAvatarUploading(false);
      e.target.value = '';
    }
  }

  async function handleProfileSubmit(e) {
    e.preventDefault();
    setProfileError('');
    setProfileSaving(true);
    try {
      const payload = {
        ...profileForm,
        experience_years: profileForm.experience_years === '' ? null : Number(profileForm.experience_years),
      };
      const data = provider ? await providerApi.update(payload) : await providerApi.create(payload);
      setProvider(data.provider);
      setEditingProfile(false);
      if (!provider) loadMine();
    } catch (err) {
      setProfileError(err.message || 'Не удалось сохранить');
    } finally {
      setProfileSaving(false);
    }
  }

  async function handleToggleActive(listing) {
    try {
      const updated = await providerApi.updateListing(listing.id, { ...listingToPayload(listing), is_active: !listing.is_active });
      setListings((prev) => prev.map((l) => (l.id === listing.id ? { ...l, ...updated.listing } : l)));
    } catch (err) {
      alert(err.message || 'Не удалось изменить публикацию');
    }
  }

  async function handleDelete(listing) {
    const confirmText = lang === 'kz' ? `«${listing.name_ru}» жоюды растайсыз ба?` : `Удалить «${listing.name_ru}»?`;
    if (!window.confirm(confirmText)) return;
    try {
      await providerApi.deleteListing(listing.id);
      setListings((prev) => prev.filter((l) => l.id !== listing.id));
    } catch (err) {
      alert(err.message || 'Не удалось удалить');
    }
  }

  const venueCategory = categories.find(isRestaurantCategory);
  const services = listings.filter((l) => l.category_id !== venueCategory?.id);
  const restaurants = listings.filter((l) => l.category_id === venueCategory?.id);

  if (loading) return <p className="admin-table__empty">Загрузка…</p>;

  if (loadFailed) {
    return (
      <p className="admin-table__empty">
        <T ru="Не удалось загрузить профиль. Обновите страницу." kz="Профильді жүктеу мүмкін болмады. Бетті жаңартыңыз." en="Couldn’t load the profile. Please refresh the page." />
      </p>
    );
  }

  return (
    <div>
      {!provider && !editingProfile && (
        <div className="ws-empty">
          <span className="ws-empty__icon">🤝</span>
          <h3 className="ws-empty__title">
            <T ru="Предлагаете услуги для тоев?" kz="Той қызметтерін ұсынасыз ба?" />
          </h3>
          <p className="ws-empty__text">
            <T
              ru="Заполните короткий профиль и добавьте свою услугу в каталог MEREYTOI."
              kz="Қысқаша профильді толтырып, қызметіңізді MEREYTOI каталогына қосыңыз."
            />
          </p>
          <button type="button" className="btn btn--gold" onClick={startBecomeProvider}>
            <T ru="Стать услугодателем" kz="Қызмет көрсетуші болу" />
          </button>
        </div>
      )}

      {editingProfile && (
        <form className="contacts__form provider-form-card" onSubmit={handleProfileSubmit}>
          <h2 className="admin-section-title" style={{ marginTop: 0 }}>
            {provider ? <T ru="Профиль услугодателя" kz="Қызмет көрсетуші профилі" /> : <T ru="Стать услугодателем" kz="Қызмет көрсетуші болу" />}
          </h2>
          <label>
            <span><T ru="Имя / название" kz="Аты / атауы" /></span>
            <input value={profileForm.display_name} onChange={(e) => setProfileForm((v) => ({ ...v, display_name: e.target.value }))} required />
          </label>
          <label>
            <span><T ru="Город" kz="Қала" /></span>
            <input value={profileForm.city} onChange={(e) => setProfileForm((v) => ({ ...v, city: e.target.value }))} />
          </label>
          <label>
            <span><T ru="Краткое описание" kz="Қысқаша сипаттама" /></span>
            <textarea rows="3" value={profileForm.description} onChange={(e) => setProfileForm((v) => ({ ...v, description: e.target.value }))} />
          </label>
          <label>
            <span><T ru="Опыт, лет (необязательно)" kz="Тәжірибе, жыл (міндетті емес)" en="Experience, years (optional)" /></span>
            <input type="number" min="0" max="80" value={profileForm.experience_years} onChange={(e) => setProfileForm((v) => ({ ...v, experience_years: e.target.value }))} />
          </label>
          <label>
            <span><T ru="Контактный телефон бизнеса" kz="Бизнестің байланыс телефоны" en="Business contact phone" /></span>
            <input type="tel" value={profileForm.phone} onChange={(e) => setProfileForm((v) => ({ ...v, phone: e.target.value }))} placeholder="+7 700 000 00 00" />
            <small><T ru="Необязательно. Номер будет виден клиентам" kz="Міндетті емес. Нөмірді клиенттер көреді" en="Optional. Clients will see this number" /></small>
          </label>
          <div className="form-row">
            <label>
              <span>WhatsApp</span>
              <input type="tel" value={profileForm.whatsapp} onChange={(e) => setProfileForm((v) => ({ ...v, whatsapp: e.target.value }))} placeholder="+7 700 000 00 00" />
            </label>
            <label>
              <span>Telegram</span>
              <input value={profileForm.telegram} onChange={(e) => setProfileForm((v) => ({ ...v, telegram: e.target.value }))} placeholder="@username" />
            </label>
          </div>
          <label>
            <span><T ru="Аватар / логотип" kz="Аватар / логотип" /></span>
            <input type="file" accept="image/png,image/jpeg,image/webp,image/gif" onChange={handleAvatarFile} disabled={avatarUploading} />
          </label>
          {profileForm.avatar_url && (
            <div className="admin-image-thumb" style={{ width: 72, height: 72 }}>
              <img src={mediaUrl(profileForm.avatar_url)} alt="" />
            </div>
          )}

          {profileError && <p className="admin-login__error">{profileError}</p>}

          <div className="provider-form-card__actions" style={{ display: 'flex', gap: 14 }}>
            <button type="submit" className="btn btn--gold" disabled={profileSaving || avatarUploading}>
              {profileSaving ? <T ru="Сохраняем…" kz="Сақталуда…" /> : <T ru="Сохранить" kz="Сақтау" />}
            </button>
            {provider && (
              <button type="button" className="btn btn--outline" onClick={() => setEditingProfile(false)}>
                <T ru="Отмена" kz="Бас тарту" />
              </button>
            )}
          </div>
        </form>
      )}

      {/* Stays mounted while the profile form is open: a service form reaches
          it from its contact card, and what's typed there must survive. */}
      {provider && (
        <div hidden={editingProfile}>
          <div className="ws-events-head">
            <div style={{ display: 'flex', gap: 14, alignItems: 'center' }}>
              {provider.avatar_url && (
                <img src={mediaUrl(provider.avatar_url)} alt="" style={{ width: 48, height: 48, borderRadius: '50%', objectFit: 'cover' }} />
              )}
              <div>
                <h2 className="admin-section-title" style={{ margin: 0 }}>{provider.display_name}</h2>
                {provider.city && <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: 13.5 }}>{provider.city}</p>}
                {provider.experience_years != null && (
                  <p style={{ margin: 0, color: 'var(--text-muted)', fontSize: 13.5 }}>
                    <T ru="Опыт, лет" kz="Тәжірибе, жыл" en="Experience, years" />: {provider.experience_years}
                  </p>
                )}
              </div>
            </div>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10 }}>
              <button type="button" className="btn btn--outline btn--sm" onClick={startEditProfile}>
                <T ru="Профиль услугодателя" kz="Қызмет көрсетуші профилі" />
              </button>
              <button type="button" className="btn btn--gold btn--sm" onClick={() => { setManagingId(null); setServiceForm('new'); }}>
                + <T ru="Добавить услугу" kz="Қызмет қосу" />
              </button>
            </div>
          </div>

          {serviceForm && (
            <div style={{ margin: '20px 0' }}>
              <ProviderServiceForm
                key={serviceForm === 'new' ? serviceForm : serviceForm.id}
                categories={categories}
                provider={provider}
                onEditContact={startEditProfile}
                listingId={typeof serviceForm === 'string' ? undefined : serviceForm.id}
                initial={
                  serviceForm === 'new'
                    ? { city: provider.city || '' }
                    : listingToPayload(serviceForm)
                }
                onSaved={(saved) => {
                  // Newly a restaurant: straight on to its halls and menus.
                  if (saved?.category_id === venueCategory?.id) setManagingId(saved.id);
                  setServiceForm(null);
                  loadMine();
                }}
                onCancel={() => setServiceForm(null)}
              />
            </div>
          )}

          {managingId && (
            <ProviderRestaurantManager
              key={managingId}
              listingId={managingId}
              categories={categories}
              provider={provider}
              onEditContact={startEditProfile}
              onSaved={(saved) => {
                loadMine();
                // Now an ordinary service: nothing left to manage here.
                if (saved && saved.category_id !== venueCategory?.id) setManagingId(null);
              }}
              onClose={() => setManagingId(null)}
            />
          )}

          {promoting && (
            <PromotionPanel key={promoting.id} listing={promoting} onClose={() => setPromoting(null)} />
          )}

          {restaurants.length > 0 && (
            <>
              <h3 className="admin-section-title"><T ru="Мои рестораны" kz="Менің мейрамханаларым" en="My restaurants" /></h3>
              <div className="admin-table-wrap">
                <table className="admin-table">
                  <tbody>
                    {restaurants.map((l) => (
                      <tr key={l.id}>
                        <td className="admin-table__name-cell">
                          {l.image_urls?.[0] ? <img src={mediaUrl(l.image_urls[0])} alt="" className="admin-table__thumb" /> : null}
                          {lang === 'kz' ? l.name_kz : l.name_ru}
                        </td>
                        <td>{l.city || '—'}</td>
                        <td>
                          <button type="button" className="admin-table__link" onClick={() => handleToggleActive(l)}>
                            {l.is_active ? <T ru="Опубликовано" kz="Жарияланды" /> : <T ru="Скрыто" kz="Жасырылған" />}
                          </button>
                        </td>
                        <td className="admin-table__actions">
                          <button type="button" className="admin-table__link" onClick={() => { setServiceForm(null); setManagingId(l.id); }}>
                            <T ru="Управлять" kz="Басқару" en="Manage" />
                          </button>
                          {/* Only the owner promotes; managers don't see it. */}
                          {l.role === 'owner' && (
                            <button type="button" className="admin-table__link" onClick={() => setPromoting(l)}>
                              <T ru="Продвигать" kz="Жарнамалау" />
                            </button>
                          )}
                          <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(l)}>
                            <T ru="Удалить" kz="Жою" />
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          <h3 className="admin-section-title"><T ru="Мои услуги" kz="Менің қызметтерім" /></h3>
          {services.length === 0 && (
            <p className="admin-table__empty"><T ru="Пока нет ни одной услуги" kz="Әзірге қызмет жоқ" /></p>
          )}
          {services.length > 0 && (
            <div className="admin-table-wrap">
              <table className="admin-table">
                <thead>
                  <tr>
                    <th><T ru="Название" kz="Атауы" /></th>
                    <th><T ru="Город" kz="Қала" /></th>
                    <th><T ru="Цена" kz="Бағасы" /></th>
                    <th><T ru="Публикация" kz="Жариялау" /></th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  {services.map((l) => (
                    <tr key={l.id}>
                      <td className="admin-table__name-cell">
                        {l.image_urls?.[0] ? <img src={mediaUrl(l.image_urls[0])} alt="" className="admin-table__thumb" /> : <span>{l.emoji}</span>}
                        {lang === 'kz' ? l.name_kz : l.name_ru}
                      </td>
                      <td>{l.city || '—'}</td>
                      <td>{l.price > 0 ? formatPrice(l.price) : (lang === 'kz' ? 'Сұраныс бойынша' : 'По запросу')}</td>
                      <td>
                        <button type="button" className="admin-table__link" onClick={() => handleToggleActive(l)}>
                          {l.is_active ? <T ru="Опубликовано" kz="Жарияланды" /> : <T ru="Скрыто" kz="Жасырын" />}
                        </button>
                      </td>
                      <td className="admin-table__actions">
                        <button type="button" className="admin-table__link" onClick={() => { setManagingId(null); setServiceForm(l); }}>
                          <T ru="Изменить" kz="Өзгерту" />
                        </button>
                        {l.role === 'owner' && (
                          <button type="button" className="admin-table__link" onClick={() => setPromoting(l)}>
                            <T ru="Продвигать" kz="Жарнамалау" />
                          </button>
                        )}
                        <button type="button" className="admin-table__link admin-table__link--danger" onClick={() => handleDelete(l)}>
                          <T ru="Удалить" kz="Жою" />
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
