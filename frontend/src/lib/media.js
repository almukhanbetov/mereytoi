const API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8090';

/** Turns a backend-relative path like "/uploads/x.png" into an absolute URL. */
export function mediaUrl(path) {
  if (!path) return path;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return `${API_URL}${path}`;
}
