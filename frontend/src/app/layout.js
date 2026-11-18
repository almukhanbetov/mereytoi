import localFont from "next/font/local";
import Script from "next/script";
import { GoogleTagManager } from "@next/third-parties/google";
import "./globals.css";
import AppProviders from "@/context/AppProviders";
import { AuthProvider } from "@/context/AuthContext";
import AccountBlockedNotice from "@/components/AccountBlockedNotice";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import CartDrawer from "@/components/CartDrawer";
import CursorGlow from "@/components/CursorGlow";
import BackToTop from "@/components/BackToTop";
import FloatingManagerWidget from "@/components/FloatingManagerWidget";
import AiAssistantWidget from "@/components/AiAssistantWidget";

// Self-hosted so the build never fetches Google Fonts (see fonts/README.md).
// The weight ranges match the weights the site used to load from Google:
// other weights are clamped to the nearest one, as before. The metric-matched
// fallbacks keep the exact values next/font/google generated; they live in
// globals.css («… Fallback» @font-face).
const playfair = localFont({
  src: "./fonts/PlayfairMEREYTOIWeb-wght.woff2",
  variable: "--font-playfair",
  weight: "500 800",
  style: "normal",
  display: "swap",
  adjustFontFallback: false,
  fallback: ["Playfair Display Fallback"],
});

const montserrat = localFont({
  src: "./fonts/Montserrat-wght.woff2",
  variable: "--font-montserrat",
  weight: "300 700",
  style: "normal",
  display: "swap",
  adjustFontFallback: false,
  fallback: ["Montserrat Fallback"],
});

export const metadata = {
  title: "MEREYTOI — Той және мерекелерді ұйымдастыру",
  description: "MEREYTOI — организация тоев и торжеств премиум-класса: декор, банкет, шоу-программа, фото и видео.",
  icons: {
    icon: "data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>✨</text></svg>",
  },
};

export default function RootLayout({ children }) {
  return (
    <html
      lang="ru"
      data-scroll-behavior="smooth"
      className={`${playfair.variable} ${montserrat.variable}`}
      suppressHydrationWarning
    >
      <body suppressHydrationWarning>
        <GoogleTagManager gtmId="GTM-579XJ2GM" />
        <Script id="theme-lang-init" strategy="beforeInteractive">
          {`
            try {
              var theme = localStorage.getItem('mereytoi-theme') || 'dark';
              if (theme === 'light') document.documentElement.setAttribute('data-theme', 'light');
              var lang = localStorage.getItem('mereytoi-lang') || 'ru';
              document.documentElement.lang = lang;
            } catch (e) {}
          `}
        </Script>
        <AuthProvider>
          <AppProviders>
            <CursorGlow />
            <Header />
            {children}
            <Footer />
            <BackToTop />
            <CartDrawer />
            <FloatingManagerWidget />
            <AiAssistantWidget />
            <AccountBlockedNotice />
          </AppProviders>
        </AuthProvider>
      </body>
    </html>
  );
}
