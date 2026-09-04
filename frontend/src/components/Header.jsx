'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import { useLang, useTheme, useCart, T } from '@/context/AppProviders';
import { useAuth } from '@/context/AuthContext';
import { AGENCY_WHATSAPP_DIGITS } from '@/lib/agencyContact';
import { trackWhatsAppClick } from '@/lib/whatsapp';
import NotificationBell from '@/components/NotificationBell';

const NAV_LINKS = [
  { href: '/', ru: 'Главная', kz: 'Басты бет' },
  { href: '/services', ru: 'Услуги', kz: 'Қызметтер' },
  { href: '/#clients', ru: 'Клиенты', kz: 'Клиенттер' },
  { href: '/#reviews', ru: 'Отзывы', kz: 'Пікірлер' },
  { href: '/#contacts', ru: 'Контакты', kz: 'Байланыс' },
];

const HEADER_WHATSAPP_MESSAGE = 'Здравствуйте! Хочу заказать проведение мероприятия в MEREYTOI.';
const HEADER_WHATSAPP_LINK = `https://wa.me/${AGENCY_WHATSAPP_DIGITS}?text=${encodeURIComponent(HEADER_WHATSAPP_MESSAGE)}`;

export default function Header() {
  const { lang, toggleLang } = useLang();
  const { toggleTheme } = useTheme();
  const { count, openDrawer } = useCart();
  const { isAuthenticated, user } = useAuth();
  const pathname = usePathname();
  const [scrolled, setScrolled] = useState(false);
  const [navOpen, setNavOpen] = useState(false);

  useEffect(() => {
    function onScroll() {
      setScrolled(window.scrollY > 40);
    }
    document.addEventListener('scroll', onScroll, { passive: true });
    onScroll();
    return () => document.removeEventListener('scroll', onScroll);
  }, []);

  if (pathname.startsWith('/admin')) return null;

  return (
    <header className={`header${scrolled ? ' is-scrolled' : ''}`} id="header">
      <div className="container header__inner">
        <Link href="/" className="logo">
          <span className="logo__mark">M</span>
          <span className="logo__text">MEREY<em>TOI</em></span>
        </Link>

        <nav className={`nav${navOpen ? ' is-open' : ''}`} id="mainNav">
          <ul className="nav__list">
            {NAV_LINKS.map((link) => {
              const isActive = (link.href === '/services' && pathname.startsWith('/services'))
                || (link.href === '/' && pathname === '/');
              return (
                <li key={link.href}>
                  <Link
                    href={link.href}
                    className={`nav__link${isActive ? ' is-active' : ''}`}
                    onClick={() => setNavOpen(false)}
                  >
                    <T ru={link.ru} kz={link.kz} />
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="header__actions">
          <button className="theme-switch" onClick={toggleTheme} aria-label="Тақырыпты ауыстыру / Переключить тему">
            <span className="theme-switch__icon theme-switch__icon--sun">☀</span>
            <span className="theme-switch__icon theme-switch__icon--moon">☾</span>
          </button>
          <button className="lang-switch" onClick={toggleLang} aria-label="Тілді ауыстыру / Переключить язык / Switch language">
            {lang === 'ru' ? 'РУС' : lang === 'kz' ? 'ҚАЗ' : 'ENG'}
          </button>
          <button className="cart-icon" id="cart-icon" onClick={openDrawer} aria-label="Себет / Корзина">
            🛍
            <span className={`cart-icon__badge${count > 0 ? ' is-visible' : ''}`}>{count}</span>
          </button>
          <NotificationBell />
          <Link
            href={isAuthenticated ? '/profile' : '/login'}
            className="cart-icon"
            aria-label={isAuthenticated ? 'Профиль' : 'Войти'}
            title={isAuthenticated ? user?.name : undefined}
          >
            👤
          </Link>
          <a
            href={HEADER_WHATSAPP_LINK}
            className="btn btn--gold btn--sm"
            target="_blank"
            rel="noopener noreferrer"
            onClick={trackWhatsAppClick}
          >
            <T ru="Заказать той" kz="Өтінім қалдыру" />
          </a>
          <button
            className={`burger${navOpen ? ' is-open' : ''}`}
            onClick={() => setNavOpen((v) => !v)}
            aria-label="Меню"
          >
            <span></span><span></span><span></span>
          </button>
        </div>
      </div>
    </header>
  );
}
