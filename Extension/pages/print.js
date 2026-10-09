(async () => {
  const { h } = SV;
  const I = SV_I18N;
  const t = (...args) => I.t(...args);
  await Page.init();
  document.documentElement.dataset.theme = 'light';

  const id = location.hash.slice(1);
  const key = `print:${id}`;
  const doc = (await chrome.storage.session.get(key))[key];
  const article = document.getElementById('doc');
  const bar = document.getElementById('bar');
  if (!doc) {
    article.append(h('p', { text: t('printGone') }));
    return;
  }
  document.title = doc.title;
  document.documentElement.lang = doc.lang || I.lang;

  // The body is the reader's cleaned copy of the page; parse it inertly and keep only safe markup.
  const parsed = new DOMParser().parseFromString(`<body>${doc.html}</body>`, 'text/html');
  for (const el of parsed.querySelectorAll('script, style, iframe, object, embed, form, link, meta, base')) el.remove();
  for (const el of parsed.body.querySelectorAll('*')) {
    for (const attr of [...el.attributes]) {
      if (/^on/i.test(attr.name) || (/^(href|src)$/i.test(attr.name) && /^\s*javascript:/i.test(attr.value))) el.removeAttribute(attr.name);
    }
  }

  article.append(
    h('div', { class: 'kicker', text: doc.site || '' }),
    h('h1', { class: 'title', text: doc.title }),
    doc.author || doc.published ? h('div', { class: 'byline', text: [doc.author, doc.published].filter(Boolean).join(' · ') }) : null,
    ...parsed.body.childNodes,
    h('div', { class: 'source', text: doc.url }));

  bar.append(
    SV.mark(20),
    h('span', { class: 'grow', text: t('printHint') }),
    h('button', { class: 'plain', type: 'button', onclick: () => window.close() }, t('close')),
    h('button', { class: 'primary', type: 'button', onclick: () => window.print() }, SV.icon('printer', 16), t('printSave')));

  chrome.storage.session.remove(key).catch(() => {});
  await Promise.race([
    Promise.all([...article.querySelectorAll('img')].map((img) => (img.complete ? null : new Promise((resolve) => {
      img.addEventListener('load', resolve, { once: true });
      img.addEventListener('error', resolve, { once: true });
    })))),
    new Promise((resolve) => setTimeout(resolve, 2500))
  ]);
  setTimeout(() => window.print(), 250);
})();
