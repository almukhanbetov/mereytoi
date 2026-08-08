'use client';

/**
 * Animates a star flying from the clicked "add to cart" button to the
 * header cart icon, instead of the cart drawer sliding open on every add.
 * Follows a quadratic-bezier arc (a straight CSS transition can't curve)
 * so the star visibly lifts off before curving down into the cart.
 */
function easeInOutQuad(t) {
  return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

export function flyToCart(sourceEl) {
  if (typeof window === 'undefined' || !sourceEl) return;
  const cartEl = document.getElementById('cart-icon');
  if (!cartEl) return;

  const sourceRect = sourceEl.getBoundingClientRect();
  const cartRect = cartEl.getBoundingClientRect();

  const startX = sourceRect.left + sourceRect.width / 2;
  const startY = sourceRect.top + sourceRect.height / 2;
  const endX = cartRect.left + cartRect.width / 2;
  const endY = cartRect.top + cartRect.height / 2;

  // Control point lifted well above the straight line between the two
  // points, so the interpolated path arcs upward like a launch/takeoff
  // before curving back down into the cart icon.
  const arcHeight = Math.max(140, Math.abs(endX - startX) * 0.5);
  const controlX = (startX + endX) / 2;
  const controlY = Math.min(startY, endY) - arcHeight;

  const star = document.createElement('span');
  star.textContent = '⭐';
  star.className = 'fly-to-cart';
  document.body.appendChild(star);

  const duration = 750;
  const startTime = performance.now();

  function frame(now) {
    const t = Math.min((now - startTime) / duration, 1);
    const e = easeInOutQuad(t);

    const x = (1 - e) ** 2 * startX + 2 * (1 - e) * e * controlX + e ** 2 * endX;
    const y = (1 - e) ** 2 * startY + 2 * (1 - e) * e * controlY + e ** 2 * endY;

    const scale = 1 - 0.7 * e;
    const rotate = 320 * e;
    const opacity = t < 0.75 ? 1 : 1 - (t - 0.75) / 0.25;

    star.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%) scale(${scale}) rotate(${rotate}deg)`;
    star.style.opacity = String(opacity);

    if (t < 1) {
      requestAnimationFrame(frame);
    } else {
      star.remove();
      cartEl.classList.add('is-bump');
      setTimeout(() => cartEl.classList.remove('is-bump'), 320);
    }
  }

  requestAnimationFrame(frame);
}
