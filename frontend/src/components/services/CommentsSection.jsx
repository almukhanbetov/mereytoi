'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Reveal from '@/components/Reveal';
import { T, useLang } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { commentsApi } from '@/lib/commentsApi';

function formatDate(iso) {
  return new Date(iso).toLocaleDateString('ru-RU', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

function Stars({ value, onChange }) {
  return (
    <div className="comment-stars" role={onChange ? 'radiogroup' : undefined}>
      {[1, 2, 3, 4, 5].map((n) => (
        <span
          key={n}
          className={`comment-stars__star${n <= value ? ' is-filled' : ''}${onChange ? ' is-interactive' : ''}`}
          onClick={onChange ? () => onChange(n) : undefined}
        >
          ★
        </span>
      ))}
    </div>
  );
}

export default function CommentsSection({ listingId }) {
  const { lang } = useLang();
  const { isAuthenticated } = useAuth();

  const [comments, setComments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [rating, setRating] = useState(5);
  const [text, setText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    commentsApi.list(listingId)
      .then((d) => setComments(d.comments || []))
      .finally(() => setLoading(false));
  }, [listingId]);

  async function handleSubmit(e) {
    e.preventDefault();
    if (!text.trim()) return;
    setError('');
    setSubmitting(true);
    try {
      await commentsApi.create(listingId, rating, text.trim());
      setSubmitted(true);
      setText('');
      setRating(5);
    } catch (err) {
      setError(err.message || (lang === 'kz' ? 'Жіберу сәтсіз аяқталды' : 'Не удалось отправить'));
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="comments-section">
      <div className="container">
        <Reveal as="h2" className="section-title" style={{ textAlign: 'left', margin: '0 0 30px' }}>
          <T ru="Комментарии" kz="Пікірлер" />
        </Reveal>

        {isAuthenticated ? (
          <form className="comment-form" onSubmit={handleSubmit}>
            <Stars value={rating} onChange={setRating} />
            <textarea
              className="comment-form__text"
              value={text}
              onChange={(e) => setText(e.target.value)}
              placeholder={lang === 'kz' ? 'Пікіріңізді жазыңыз…' : 'Поделитесь впечатлением…'}
              required
            />
            {error && <p className="admin-login__error">{error}</p>}
            <button type="submit" className="btn btn--gold btn--sm" disabled={submitting}>
              {submitting ? <T ru="Отправляем…" kz="Жіберілуде…" /> : <T ru="Отправить" kz="Жіберу" />}
            </button>
            <p className={`comment-form__success${submitted ? ' is-visible' : ''}`}>
              <T
                ru="Спасибо! Комментарий отправлен на модерацию и появится после проверки."
                kz="Рахмет! Пікір модерацияға жіберілді, тексерістен кейін көрінеді."
              />
            </p>
          </form>
        ) : (
          <p className="comment-form__login-prompt">
            <T ru="Чтобы оставить комментарий, " kz="Пікір қалдыру үшін " />
            <Link href="/login"><T ru="войдите в аккаунт" kz="аккаунтқа кіріңіз" /></Link>.
          </p>
        )}

        {!loading && comments.length === 0 && (
          <p className="listing-empty"><T ru="Пока нет комментариев" kz="Әзірге пікірлер жоқ" /></p>
        )}

        <div className="comment-list">
          {comments.map((c) => (
            <div className="comment" key={c.id}>
              <div className="comment__avatar">{c.user_name?.[0]?.toUpperCase() || '?'}</div>
              <div className="comment__body">
                <div className="comment__head">
                  <span className="comment__author">{c.user_name}</span>
                  <span className="comment__date">{formatDate(c.created_at)}</span>
                </div>
                <Stars value={c.rating} />
                <p className="comment__text">{c.text}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
