'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { authApi, getUserToken, setUserToken, clearUserToken } from '@/lib/authApi';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  const loadUser = useCallback(async () => {
    const token = getUserToken();
    if (!token) {
      setUser(null);
      setLoading(false);
      return;
    }
    try {
      const { user } = await authApi.me();
      setUser(user);
    } catch {
      clearUserToken();
      setUser(null);
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

  const logout = useCallback(() => {
    clearUserToken();
    setUser(null);
  }, []);

  const updateProfile = useCallback(async (name, phone) => {
    const { user } = await authApi.updateMe(name, phone);
    setUser(user);
    return user;
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, isAuthenticated: !!user, register, login, logout, updateProfile }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}
