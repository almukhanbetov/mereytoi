'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { T } from '@/context/AppProviders';

export default function Footer() {
  const pathname = usePathname();
  if (pathname.startsWith('/admin')) return null;

  return (
    <footer className="footer">
      <div className="container footer__inner">
        <Link href="/" className="logo logo--footer">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </Link>
        <p className="footer__copy">
          <T ru="© 2026 MEREYTOI. Все права защищены." kz="© 2026 MEREYTOI. Барлық құқықтар қорғалған." />
        </p>
        <div className="footer__nav">
          <Link href="/services"><T ru="Услуги" kz="Қызметтер" /></Link>
          <Link href="/#clients"><T ru="Клиенты" kz="Клиенттер" /></Link>
          <Link href="/#reviews"><T ru="Отзывы" kz="Пікірлер" /></Link>
          <Link href="/#contacts"><T ru="Контакты" kz="Байланыс" /></Link>
        </div>
      </div>
    </footer>
  );
}
