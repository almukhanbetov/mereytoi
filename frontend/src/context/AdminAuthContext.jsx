'use client';

import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { adminApi, getToken, setToken, clearToken } from '@/lib/adminApi';

const AdminAuthContext = createContext(null);

export function AdminAuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  const loadUser = useCallback(async () => {
    const token = getToken();
    if (!token) {
      setUser(null);
      setLoading(false);
      return;
    }
    try {
      const { user } = await adminApi.me();
      setUser(user);
    } catch {
      clearToken();
      setUser(null);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadUser();
  }, [loadUser]);

  const login = useCallback(async (email, password) => {
    const { user, token } = await adminApi.login(email, password);
    if (user.role !== 'admin') {
      throw new Error('У этого аккаунта нет прав администратора');
    }
    setToken(token);
    setUser(user);
    return user;
  }, []);

  const logout = useCallback(() => {
    clearToken();
    setUser(null);
  }, []);

  const isAdmin = !!user && user.role === 'admin';

  return (
    <AdminAuthContext.Provider value={{ user, loading, isAdmin, login, logout }}>
      {children}
    </AdminAuthContext.Provider>
  );
}

export function useAdminAuth() {
  return useContext(AdminAuthContext);
}
