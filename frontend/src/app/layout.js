import { Playfair_Display, Montserrat } from "next/font/google";
import Script from "next/script";
import { GoogleTagManager } from "@next/third-parties/google";
import "./globals.css";
import AppProviders from "@/context/AppProviders";
import { AuthProvider } from "@/context/AuthContext";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import CartDrawer from "@/components/CartDrawer";
import CursorGlow from "@/components/CursorGlow";
import BackToTop from "@/components/BackToTop";

const playfair = Playfair_Display({
  variable: "--font-playfair",
  subsets: ["latin", "cyrillic"],
  weight: ["500", "600", "700", "800"],
});

const montserrat = Montserrat({
  variable: "--font-montserrat",
  subsets: ["latin", "cyrillic"],
  weight: ["300", "400", "500", "600", "700"],
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
          </AppProviders>
        </AuthProvider>
      </body>
    </html>
  );
}
