'use client';

// The one place the session token is actually stored — both the customer
// (`authApi`/`AuthContext`) and admin (`adminApi`/`AdminAuthContext`) call
// sites go through this now, since they're both just `/api/auth/login`
// against the same account/JWT (see the 10C stage report for the split
// this replaces). Kept as its own tiny module rather than living inside
// `authApi.js` or `adminApi.js`, so neither one "owns" the shared
// primitive the other depends on.
const TOKEN_KEY = 'mereytoi-user-token';

export function getToken() {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token) {
  localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken() {
  localStorage.removeItem(TOKEN_KEY);
}
