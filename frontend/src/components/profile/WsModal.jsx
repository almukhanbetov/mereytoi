'use client';

/** A modal on desktop, a bottom sheet on mobile (same markup — the
 * .ws-modal-overlay/.ws-modal breakpoint in globals.css handles the
 * difference), used anywhere the workspace needs a focused overlay instead
 * of a full page: a service's comment thread, the comparison view, "Ещё". */
export default function WsModal({ title, onClose, children }) {
  return (
    <div className="ws-modal-overlay" onClick={onClose}>
      <div className="ws-modal" onClick={(e) => e.stopPropagation()}>
        <div className="ws-modal__head">
          <h3 className="ws-modal__title">{title}</h3>
          <button type="button" className="admin-table__link" onClick={onClose}>✕</button>
        </div>
        {children}
      </div>
    </div>
  );
}
