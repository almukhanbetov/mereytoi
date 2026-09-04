'use client';

import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

const LangContext = createContext(null);
const ThemeContext = createContext(null);

const LANG_KEY = 'mereytoi-lang';
const THEME_KEY = 'mereytoi-theme';

/* ---------- Language ---------- */
function LangProvider({ children }) {
  const [lang, setLangState] = useState('ru');

  useEffect(() => {
    const saved = localStorage.getItem(LANG_KEY) || 'ru';
    setLangState(saved);
    document.documentElement.lang = saved;
  }, []);

  const setLang = useCallback((next) => {
    setLangState(next);
    document.documentElement.lang = next;
    localStorage.setItem(LANG_KEY, next);
  }, []);

  // ru -> kz -> en -> ru. EN was added for the event-request/booking flow
  // (the one part of the site with authored English copy so far); every
  // older `<T ru kz/>` call with no `en` prop just falls back to `ru` in EN
  // mode — graceful degradation, not breakage, while that copy is filled in
  // screen by screen.
  const toggleLang = useCallback(() => {
    setLang(lang === 'ru' ? 'kz' : lang === 'kz' ? 'en' : 'ru');
  }, [lang, setLang]);

  const value = useMemo(() => ({ lang, setLang, toggleLang }), [lang, setLang, toggleLang]);
  return <LangContext.Provider value={value}>{children}</LangContext.Provider>;
}

export function useLang() {
  return useContext(LangContext);
}

/** Tri-lingual text helper — mirrors the original data-kz/data-ru swap, plus
 * an optional `en` for newer screens; falls back to `ru` where `en` hasn't
 * been authored yet. */
export function T({ ru, kz, en }) {
  const { lang } = useLang();
  if (lang === 'kz') return kz;
  if (lang === 'en') return en ?? ru;
  return ru;
}

/* ---------- Theme ---------- */
function ThemeProvider({ children }) {
  const [theme, setThemeState] = useState('dark');

  useEffect(() => {
    const saved = localStorage.getItem(THEME_KEY) || 'dark';
    setThemeState(saved);
    if (saved === 'light') document.documentElement.setAttribute('data-theme', 'light');
    else document.documentElement.removeAttribute('data-theme');
  }, []);

  const setTheme = useCallback((next) => {
    setThemeState(next);
    if (next === 'light') document.documentElement.setAttribute('data-theme', 'light');
    else document.documentElement.removeAttribute('data-theme');
    localStorage.setItem(THEME_KEY, next);
  }, []);

  const toggleTheme = useCallback(() => {
    setTheme(theme === 'dark' ? 'light' : 'dark');
  }, [theme, setTheme]);

  const value = useMemo(() => ({ theme, setTheme, toggleTheme }), [theme, setTheme, toggleTheme]);
  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  return useContext(ThemeContext);
}

/* ---------- Cart (booking selections) ---------- */
const CartContext = createContext(null);
const CART_KEY = 'mereytoi-booking-cart';
const MY_BOOKINGS_KEY = 'mereytoi-my-bookings';

function CartProvider({ children }) {
  const [items, setItems] = useState([]);
  const [isOpen, setIsOpen] = useState(false);
  const [myBookingRefs, setMyBookingRefs] = useState([]);

  useEffect(() => {
    try {
      setItems(JSON.parse(localStorage.getItem(CART_KEY)) || []);
    } catch {
      setItems([]);
    }
    try {
      setMyBookingRefs(JSON.parse(localStorage.getItem(MY_BOOKINGS_KEY)) || []);
    } catch {
      setMyBookingRefs([]);
    }
  }, []);

  const addBookingRef = useCallback((ref) => {
    if (!ref) return;
    setMyBookingRefs((prev) => {
      const next = [ref, ...prev.filter((r) => r !== ref)].slice(0, 20);
      localStorage.setItem(MY_BOOKINGS_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  function persist(next) {
    setItems(next);
    localStorage.setItem(CART_KEY, JSON.stringify(next));
  }

  const addItem = useCallback((item) => {
    setItems((prev) => {
      const next = [...prev.filter((i) => i.listingId !== item.listingId), item];
      localStorage.setItem(CART_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  const removeItem = useCallback((listingId) => {
    setItems((prev) => {
      const next = prev.filter((i) => i.listingId !== listingId);
      localStorage.setItem(CART_KEY, JSON.stringify(next));
      return next;
    });
  }, []);

  const clear = useCallback(() => persist([]), []);

  const count = items.length;
  const total = useMemo(() => items.reduce((s, i) => s + i.totalPrice, 0), [items]);

  const openDrawer = useCallback(() => setIsOpen(true), []);
  const closeDrawer = useCallback(() => setIsOpen(false), []);

  const value = useMemo(
    () => ({ items, addItem, removeItem, clear, count, total, isOpen, openDrawer, closeDrawer, myBookingRefs, addBookingRef }),
    [items, addItem, removeItem, clear, count, total, isOpen, openDrawer, closeDrawer, myBookingRefs, addBookingRef]
  );

  return <CartContext.Provider value={value}>{children}</CartContext.Provider>;
}

export function useCart() {
  return useContext(CartContext);
}

/* ---------- Root wrapper ---------- */
export default function AppProviders({ children }) {
  return (
    <LangProvider>
      <ThemeProvider>
        <CartProvider>{children}</CartProvider>
      </ThemeProvider>
    </LangProvider>
  );
}
