/**
 * Light and dark.
 *
 * Dark is what `:root` says in app.css, so it needs no marker; light is stamped
 * onto the document element as `data-theme="light"` and the token block under
 * `:root[data-theme='light']` takes over. Nothing else in the application looks
 * at the theme — components ask for role tokens and get whichever palette is
 * current.
 *
 * The same three lines run twice: once here, and once as the inline guard at
 * the top of index.html, which stamps the attribute before the first paint so
 * a light-mode viewer never sees a dark flash. If you change what this writes,
 * change the guard too.
 */

export type Theme = 'dark' | 'light' | 'system';

const LIGHT_QUERY = '(prefers-color-scheme: light)';

/**
 * 'system' asks the shell, which on a television usually has no opinion and
 * answers dark. That is the right answer, so there is no fallback to write.
 */
export function resolveTheme(theme: Theme): 'dark' | 'light' {
  if (theme !== 'system') return theme;
  return window.matchMedia(LIGHT_QUERY).matches ? 'light' : 'dark';
}

export function applyTheme(theme: Theme): void {
  const root = document.documentElement;
  if (resolveTheme(theme) === 'light') root.setAttribute('data-theme', 'light');
  else root.removeAttribute('data-theme');
}

/** Fires when the shell's own palette changes. Only meaningful under 'system'. */
export function onSystemThemeChange(handler: () => void): () => void {
  const query = window.matchMedia(LIGHT_QUERY);
  query.addEventListener('change', handler);
  return () => query.removeEventListener('change', handler);
}
