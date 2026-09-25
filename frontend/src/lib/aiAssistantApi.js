'use client';

const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

// AI event-planning assistant — Этап 1. Deliberately separate from
// managerChatApi.js: public (no auth token sent, matches the backend route
// having no RequireAuth), and stateless — the caller resends the whole
// message history every turn (see AiAssistantWidget.jsx), there's no
// server-side conversation to reopen like Manager Chat's own start()/get().
export const aiAssistantApi = {
  // messages: [{ role: 'user'|'assistant', content: string }, ...]
  chat: async (messages, locale) => {
    const res = await fetch(`${API_URL}/api/ai-assistant/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages, locale }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(data.error || `Request failed (${res.status})`);
      err.unavailable = Boolean(data.unavailable);
      throw err;
    }
    return data; // { reply, listings }
  },
};
