'use client';

import { useEffect, useMemo, useState } from 'react';
import { useCart, useLang, T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { formatPrice } from '@/lib/format';
import { mediaUrl } from '@/lib/media';
import { createBooking, lookupBookings } from '@/lib/bookingApi';
import { authApi, getUserToken } from '@/lib/authApi';
import { buildWhatsAppLink } from '@/lib/whatsapp';

const STATUS_LABELS = {
  new: { ru: 'Новая', kz: 'Жаңа' },
  contacted: { ru: 'Связались', kz: 'Хабарластық' },
  confirmed: { ru: 'Подтверждена', kz: 'Расталды' },
  cancelled: { ru: 'Отменена', kz: 'Болдырылмады' },
};

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

export default function CartDrawer() {
  const { items, removeItem, clear, count, total, isOpen, closeDrawer, myBookingRefs, addBookingRef } = useCart();
  const { lang } = useLang();
  const { user, isAuthenticated } = useAuth();
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [checkedOut, setCheckedOut] = useState(false);
  const [myBookings, setMyBookings] = useState([]);
  const [lastOrder, setLastOrder] = useState(null);

  const whatsappItems = items.length > 0 ? items : (lastOrder?.items || []);
  const whatsappTotal = items.length > 0 ? total : (lastOrder?.total || 0);
  const whatsappLink = useMemo(
    () => buildWhatsAppLink({ items: whatsappItems, total: whatsappTotal, phone, lang, formatPrice }),
    [whatsappItems, whatsappTotal, phone, lang]
  );

  useEffect(() => {
    document.body.classList.toggle('no-scroll', isOpen);
  }, [isOpen]);

  useEffect(() => {
    if (user) {
      setName(user.name || '');
      setPhone(user.phone || '');
    }
  }, [user]);

  useEffect(() => {
    if (!isOpen) return;
    if (isAuthenticated) {
      authApi.myBookings().then((d) => setMyBookings(d.bookings || [])).catch(() => {});
    } else if (myBookingRefs.length > 0) {
      lookupBookings(myBookingRefs).then(setMyBookings);
    }
  }, [isOpen, isAuthenticated, myBookingRefs]);

  async function handleCheckout(e) {
    e.preventDefault();
    if (count === 0) return;
    setError('');
    setSubmitting(true);
    try {
      const { booking } = await createBooking(
        {
          name,
          phone,
          items: items.map((i) => ({
            listing_id: i.listingId,
            name: i.name,
            category: i.category || '',
            guests: i.guests || 0,
            unit_price: i.unitPrice,
            total_price: i.totalPrice,
          })),
        },
        getUserToken()
      );
      if (!isAuthenticated) addBookingRef(booking.public_ref);
      setMyBookings((prev) => [booking, ...prev]);
      setLastOrder({ items, total });
      setCheckedOut(true);
      clear();
      if (!isAuthenticated) {
        setName('');
        setPhone('');
      }
      setTimeout(() => setCheckedOut(false), 2800);
    } catch (err) {
      setError(err.message || 'Не удалось отправить заявку');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <div className={`cart-overlay${isOpen ? ' is-open' : ''}`} onClick={closeDrawer} />
      <aside className={`cart-drawer${isOpen ? ' is-open' : ''}`}>
        <div className="cart-drawer__head">
          <h3><T ru="Корзина бронирований" kz="Брондау себеті" /></h3>
          <button className="cart-drawer__close" onClick={closeDrawer} aria-label="Close">✕</button>
        </div>

        <div className="cart-drawer__items">
          {items.map((item) => (
            <div className="cart-item" key={item.listingId}>
              <div
                className="cart-item__media"
                style={
                  item.image
                    ? { backgroundImage: `url(${mediaUrl(item.image)})`, backgroundSize: 'cover', backgroundPosition: 'center' }
                    : { '--c1': item.colorFrom, '--c2': item.colorTo }
                }
              >
                {!item.image && <span>{item.emoji}</span>}
              </div>
              <div className="cart-item__body">
                <p className="cart-item__name">{item.name}</p>
                {item.guests ? (
                  <p className="cart-item__breakdown">{item.guests} <T ru="чел." kz="адам" /> × {formatPrice(item.unitPrice)}</p>
                ) : null}
                <p className="cart-item__price">{formatPrice(item.totalPrice)}</p>
              </div>
              <button className="cart-item__remove" onClick={() => removeItem(item.listingId)} aria-label="Remove">✕</button>
            </div>
          ))}

          {items.length === 0 && !lastOrder && (
            <p className="cart-drawer__empty"><T ru="Вы ещё ничего не добавили" kz="Сіз әлі ештеңе қоспадыңыз" /></p>
          )}

          {myBookings.length > 0 && (
            <div className="cart-history">
              <p className="cart-history__title"><T ru="Мои заявки" kz="Менің өтінімдерім" /></p>
              {myBookings.map((b) => (
                <div className="my-booking" key={b.public_ref || b.id}>
                  <div className="my-booking__head">
                    <span className="my-booking__date">{formatDate(b.created_at)}</span>
                    <span className={`my-booking__status my-booking__status--${b.status}`}>
                      {STATUS_LABELS[b.status]?.[lang] || b.status}
                    </span>
                  </div>
                  {(b.items || []).map((it, i) => (
                    <p className="my-booking__item" key={i}>
                      {it.name}{it.guests > 0 ? ` · ${it.guests} ${lang === 'kz' ? 'адам' : 'чел.'}` : ''}
                    </p>
                  ))}
                  <div className="my-booking__total">
                    <span><T ru="Итого" kz="Барлығы" /></span>
                    <b>{formatPrice(b.total)}</b>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {items.length > 0 ? (
          <form className="cart-drawer__footer" onSubmit={handleCheckout}>
            <div className="cart-drawer__total">
              <span><T ru="Итого" kz="Барлығы" /></span>
              <b>{formatPrice(total)}</b>
            </div>

            <div className="cart-drawer__fields">
              <input
                type="text"
                placeholder={lang === 'kz' ? 'Атыңыз' : 'Ваше имя'}
                value={name}
                onChange={(e) => setName(e.target.value)}
                required
              />
              <input
                type="tel"
                placeholder={lang === 'kz' ? 'Телефон' : 'Телефон'}
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                required
              />
            </div>

            {error && <p className="admin-login__error">{error}</p>}

            <button type="submit" className="btn btn--gold btn--block" disabled={submitting}>
              {submitting ? <T ru="Отправляем…" kz="Жіберілуде…" /> : <T ru="Оформить заявку" kz="Өтінім жасау" />}
            </button>
          </form>
        ) : checkedOut ? (
          <div className="cart-drawer__footer">
            <p className="cart-drawer__success is-visible">
              <T ru="Спасибо! Мы свяжемся с вами для подтверждения." kz="Рахмет! Растау үшін сізбен байланысамыз." />
            </p>
          </div>
        ) : null}

        {(items.length > 0 || (lastOrder && lastOrder.items.length > 0)) && (
          <a className="cart-whatsapp" href={whatsappLink} target="_blank" rel="noopener noreferrer">
            <span className="cart-whatsapp__icon">💬</span>
            <span className="cart-whatsapp__body">
              <span className="cart-whatsapp__title"><T ru="Отправить в WhatsApp" kz="WhatsApp-қа жіберу" /></span>
              <span className="cart-whatsapp__desc">
                <T ru="Коммерческое предложение по выбранным услугам" kz="Таңдалған қызметтер бойынша коммерциялық ұсыныс" />
              </span>
            </span>
            <span className="cart-whatsapp__arrow">→</span>
          </a>
        )}
      </aside>
    </>
  );
}
