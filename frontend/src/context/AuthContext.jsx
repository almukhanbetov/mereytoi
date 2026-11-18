'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { authApi, getUserToken, setUserToken, clearUserToken } from '@/lib/authApi';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  // telegramLinked/preferredDeliveryChannel — additive, sibling fields on
  // the /api/auth/me response (see backend's Me() handler), not part of
  // `user` itself, so every other reader of `user` keeps its exact
  // existing shape. Surfaced here (rather than read ad hoc from
  // profile/page.js) so refreshMe below can update them together.
  const [telegramLinked, setTelegramLinked] = useState(false);
  const [preferredDeliveryChannel, setPreferredDeliveryChannel] = useState('');
  // An administrator's block on this account ({reason, blocked_until,
  // password_reset, recovery_code}), shown by AccountBlockedNotice instead
  // of a technical code or a silent sign-out.
  const [blockInfo, setBlockInfo] = useState(null);
  const noteBlock = useCallback((err) => {
    if (err?.data?.error === 'account_blocked') setBlockInfo(err.data);
  }, []);

  const loadUser = useCallback(async () => {
    const token = getUserToken();
    if (!token) {
      setUser(null);
      setTelegramLinked(false);
      setPreferredDeliveryChannel('');
      setLoading(false);
      return;
    }
    try {
      const data = await authApi.me();
      setUser(data.user);
      setTelegramLinked(!!data.telegram_linked);
      setPreferredDeliveryChannel(data.preferred_delivery_channel || '');
    } catch (err) {
      noteBlock(err);
      clearUserToken();
      setUser(null);
      setTelegramLinked(false);
      setPreferredDeliveryChannel('');
    } finally {
      setLoading(false);
    }
  }, [noteBlock]);

  useEffect(() => {
    loadUser();
  }, [loadUser]);

  // A block that arrives mid-session: any API response — from whichever
  // module made the request — that is a 401 with error "account_blocked"
  // signs the user out here and shows AccountBlockedNotice with the reason
  // and term, without a reload. Only that exact case: an ordinary 401 (an
  // expired session) or any 403 is left to the caller as before. The body
  // is read from a clone, so the caller still gets its response untouched.
  useEffect(() => {
    if (typeof window === 'undefined' || !window.fetch) return undefined;
    const original = window.fetch;
    const apiOrigin = new URL(API_URL, window.location.href).origin;
    const watched = async (...args) => {
      const res = await original(...args);
      try {
        const url = new URL(typeof args[0] === 'string' ? args[0] : args[0]?.url || '', window.location.href);
        if (res.status === 401 && url.origin === apiOrigin && getUserToken()) {
          const body = await res.clone().json().catch(() => null);
          if (body?.error === 'account_blocked') {
            setBlockInfo(body);
            clearUserToken();
            setUser(null);
          }
        }
      } catch {
        // Never let the observer break the request itself.
      }
      return res;
    };
    window.fetch = watched;
    return () => {
      if (window.fetch === watched) window.fetch = original;
    };
  }, []);

  // Also returns the account's backup code — shown once by the register
  // page, never stored anywhere on the client.
  const register = useCallback(async (name, email, phone, password) => {
    const { user, token, recovery_code: recoveryCode } = await authApi.register(name, email, phone, password);
    setUserToken(token);
    setUser(user);
    return { user, recoveryCode };
  }, []);

  // Password recovery with the backup code: signs in with the fresh session
  // (every older one is revoked by the backend) and returns the new code
  // that replaced the used one.
  const recover = useCallback(async (loginValue, code, newPassword) => {
    let result;
    try {
      result = await authApi.recover(loginValue.trim(), code, newPassword);
    } catch (err) {
      noteBlock(err);
      throw err;
    }
    const { user, token, recovery_code: recoveryCode } = result;
    setUserToken(token);
    setUser(user);
    return { user, recoveryCode };
  }, [noteBlock]);

  const login = useCallback(async (identifier, password) => {
    let result;
    try {
      result = await authApi.login(identifier, password);
    } catch (err) {
      noteBlock(err);
      throw err;
    }
    const { user, token } = result;
    setUserToken(token);
    setUser(user);
    return user;
  }, [noteBlock]);

  // Booking->account onboarding (see backend/internal/handlers/onboarding.go)
  // — same shape as login/register above, just fed by a claim link instead
  // of credentials, so the success-screen CTA/claim page opens a real
  // session through the exact same path everything else already uses.
  // event_id (additive on the backend's claim response — see auth_handler.go)
  // is returned separately, not merged into `user`, so app-wide `user`
  // state everywhere else keeps exactly its normal shape.
  const claim = useCallback(async (claimToken) => {
    const { user, token, event_id: eventId } = await authApi.claim(claimToken);
    setUserToken(token);
    setUser(user);
    return { user, eventId };
  }, []);

  const logout = useCallback(() => {
    clearUserToken();
    setUser(null);
  }, []);

  const updateProfile = useCallback(async (name, phone) => {
    const { user } = await authApi.updateMe(name, phone);
    setUser(user);
    return user;
  }, []);

  // Derived, not separately tracked — see context/AdminAuthContext.jsx,
  // which is now just a thin selector over this same session rather than a
  // second one (10C).
  const isAdmin = !!user && user.role === 'admin';

  return (
    <AuthContext.Provider
      value={{
        user,
        loading,
        isAuthenticated: !!user,
        isAdmin,
        register,
        recover,
        login,
        claim,
        logout,
        updateProfile,
        telegramLinked,
        preferredDeliveryChannel,
        // refreshMe — lets a page re-check telegram_linked after the user
        // comes back from linking in the Telegram app (see profile/page.js),
        // without re-running the whole mount-time loadUser effect.
        refreshMe: loadUser,
        blockInfo,
        clearBlockInfo: () => setBlockInfo(null),
        noteBlock,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
