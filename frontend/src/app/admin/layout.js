import { AdminAuthProvider } from "@/context/AdminAuthContext";
import AdminGuard from "@/components/admin/AdminGuard";

export const metadata = {
  title: "Админ-панель — MEREYTOI",
  robots: "noindex, nofollow",
};

export default function AdminLayout({ children }) {
  return (
    <AdminAuthProvider>
      <AdminGuard>{children}</AdminGuard>
    </AdminAuthProvider>
  );
}
