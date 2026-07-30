'use client';

import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';

export default function BackToTop() {
  const [visible, setVisible] = useState(false);
  const pathname = usePathname();

  useEffect(() => {
    function onScroll() {
      setVisible(window.scrollY > 600);
    }
    document.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => document.removeEventListener('scroll', onScroll);
  }, []);

  if (pathname.startsWith('/admin')) return null;

  return (
    <a
      href="#hero"
      className={`to-top${visible ? ' is-visible' : ''}`}
      aria-label="Up"
      onClick={(e) => {
        if (window.location.pathname !== '/') return;
        e.preventDefault();
        window.scrollTo({ top: 0, behavior: 'smooth' });
      }}
    >
      ↑
    </a>
  );
}
