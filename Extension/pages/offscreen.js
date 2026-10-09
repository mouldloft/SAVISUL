// Turns blobs parked in IndexedDB by the service worker into extension-origin blob URLs it can download.
const urls = new Map();

chrome.runtime.onMessage.addListener((message, _sender, respond) => {
  if (message?.target !== 'offscreen') return false;
  if (message.type === 'blob:url') {
    SV_DB.get('frames', `blob:${message.key}`).then((blob) => {
      if (!blob) {
        respond({ error: 'missing' });
        return;
      }
      const url = URL.createObjectURL(blob);
      urls.set(url, message.key);
      respond({ url });
    }).catch((error) => respond({ error: String(error) }));
    return true;
  }
  if (message.type === 'blob:revoke') {
    URL.revokeObjectURL(message.url);
    urls.delete(message.url);
    SV_DB.remove('frames', `blob:${message.key}`).catch(() => {});
    respond({ ok: true });
    if (!urls.size) setTimeout(() => { if (!urls.size) window.close(); }, 1000);
    return false;
  }
  return false;
});
