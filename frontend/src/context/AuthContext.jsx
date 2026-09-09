'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { authApi, getUserToken, setUserToken, clearUserToken } from '@/lib/authApi';

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
    } catch {
      clearUserToken();
      setUser(null);
      setTelegramLinked(false);
      setPreferredDeliveryChannel('');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadUser();
  }, [loadUser]);

  const register = useCallback(async (name, email, phone, password) => {
    const { user, token } = await authApi.register(name, email, phone, password);
    setUserToken(token);
    setUser(user);
    return user;
  }, []);

  const login = useCallback(async (identifier, password) => {
    const { user, token } = await authApi.login(identifier, password);
    setUserToken(token);
    setUser(user);
    return user;
  }, []);

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
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
