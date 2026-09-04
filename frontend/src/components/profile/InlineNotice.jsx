'use client';

/** A plain inline success/error line — reuses the site's existing
 * `.form-success` / `.auth-card__error` patterns instead of `window.alert`,
 * per the request flow's "no browser alert()" requirement. */
export default function InlineNotice({ type = 'success', children }) {
  if (!children) return null;
  if (type === 'error') return <p className="auth-card__error">{children}</p>;
  return <p className="form-success is-visible">{children}</p>;
}
