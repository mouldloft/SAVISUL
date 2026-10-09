(() => {
  let opening = null;

  function open() {
    opening ||= new Promise((resolve, reject) => {
      const request = indexedDB.open('savisul', 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains('shots')) db.createObjectStore('shots');
        if (!db.objectStoreNames.contains('frames')) db.createObjectStore('frames');
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => {
        opening = null;
        reject(request.error);
      };
    });
    return opening;
  }

  async function run(store, mode, action) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(store, mode);
      const request = action(tx.objectStore(store));
      tx.oncomplete = () => resolve(request ? request.result : undefined);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  }

  const put = (store, key, value) => run(store, 'readwrite', (s) => s.put(value, key));
  const get = (store, key) => run(store, 'readonly', (s) => s.get(key));
  const remove = (store, key) => run(store, 'readwrite', (s) => s.delete(key));
  const keys = (store) => run(store, 'readonly', (s) => s.getAllKeys());

  async function dropShot(id) {
    const shot = await get('shots', id);
    await remove('shots', id);
    const count = shot?.frames?.length || 0;
    for (let i = 0; i < count; i++) await remove('frames', `${id}:${i}`);
  }

  async function sweep(maxAge = 6 * 3600 * 1000) {
    const now = Date.now();
    for (const id of await keys('shots')) {
      const shot = await get('shots', id);
      if (!shot || now - (shot.created || 0) > maxAge) await dropShot(id);
    }
  }

  globalThis.SV_DB = { put, get, remove, keys, dropShot, sweep };
})();
