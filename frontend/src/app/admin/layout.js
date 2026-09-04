import AdminGuard from "@/components/admin/AdminGuard";

export const metadata = {
  title: "Админ-панель — MEREYTOI",
  robots: "noindex, nofollow",
};

// 10C: no AdminAuthProvider here anymore — useAdminAuth() (see
// context/AdminAuthContext.jsx) now reads the one shared session that the
// root layout's <AuthProvider> already provides to the whole app.
export default function AdminLayout({ children }) {
  return <AdminGuard>{children}</AdminGuard>;
}
