'use client';

import { useCallback } from 'react';
import { useAuth } from '@/context/AuthContext';

// 10C: this used to be its own Provider/Context holding a fully separate
// `user`/`loading`/token — a second, parallel session for the exact same
// backend account that AuthContext already tracks (both flows hit the same
// /api/auth/login). That's gone: this is now a thin selector over the one
// shared session, kept as its own hook (not just inlining useAuth()
// everywhere in AdminGuard/AdminShell/admin/login) purely for readability —
// "this component cares about the admin view of the session" reads better
// at each call site than re-deriving isAdmin/rewrapping login by hand.
//
// No <AdminAuthProvider> anymore — there's nothing left for it to own.
// app/admin/layout.js reads straight from the root <AuthProvider>, which
// already wraps the whole app.
export function useAdminAuth() {
  const auth = useAuth();

  const login = useCallback(
    async (identifier, password) => {
      const user = await auth.login(identifier, password);
      if (user.role !== 'admin') {
        // Never leave a non-admin "signed in" via the admin flow — roll the
        // shared session back out exactly like the old separate context did
        // before it ever persisted a token under its own key.
        auth.logout();
        throw new Error('У этого аккаунта нет прав администратора');
      }
      return user;
    },
    [auth],
  );

  return {
    user: auth.user,
    loading: auth.loading,
    isAdmin: auth.isAdmin,
    login,
    logout: auth.logout,
  };
}
