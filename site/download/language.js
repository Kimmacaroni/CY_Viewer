/* 번역은 HTML을 삽입하지 않고 텍스트와 접근성 속성만 바꾼다. */
(function(root) {
  function resolveLanguage(mode, languages) {
    if (mode === 'ko' || mode === 'en') return mode;
    return String((languages || [])[0] || 'en').toLowerCase().startsWith('ko') ? 'ko' : 'en';
  }
  if (typeof module !== 'undefined') module.exports = {resolveLanguage};
  if (typeof document === 'undefined') return;
  let mode = 'system';
  try { mode = localStorage.getItem('cy_site_language') || mode; } catch (_) {}
  const originalText = new WeakMap(), originalAttributes = new WeakMap();
  const t = (text, ...args) => {
    const language = resolveLanguage(mode, navigator.languages || [navigator.language]);
    const template = language === 'ko' ? text : (root.CyEnglish[text] || text);
    return template.replace(/\{(\d+)\}/g, (match, index) => index < args.length ? String(args[index]) : match);
  };
  root.CyLanguage = {t};
  function render() {
    const language = resolveLanguage(mode, navigator.languages || [navigator.language]);
    document.documentElement.lang = language;
    const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      if (node.parentElement.closest('script, style, select, noscript')) continue;
      if (!originalText.has(node)) originalText.set(node, node.textContent);
      const source = originalText.get(node), key = source.trim();
      if (root.CyEnglish[key]) node.textContent = source.replace(key, t(key));
    }
    for (const element of document.querySelectorAll('[alt], [aria-label], meta[name="description"]')) {
      if (!originalAttributes.has(element)) originalAttributes.set(element, {});
      const originals = originalAttributes.get(element);
      for (const attr of ['alt', 'aria-label', 'content']) {
        if (!element.hasAttribute(attr)) continue;
        originals[attr] ??= element.getAttribute(attr);
        element.setAttribute(attr, t(originals[attr]));
      }
    }
    for (const link of document.querySelectorAll('a[data-web-app], a[href^="../"]')) {
      link.setAttribute('data-web-app', 'true');
      const url = new URL(link.href); url.searchParams.set('lang', language); link.href = url.href;
    }
    root.dispatchEvent(new Event('cylanguagechange'));
  }
  const select = document.getElementById('language');
  select.value = ['ko', 'en'].includes(mode) ? mode : 'system';
  select.addEventListener('change', () => {
    mode = select.value;
    try { localStorage.setItem('cy_site_language', mode); } catch (_) {}
    render();
  });
  render();
})(globalThis);
