/* 최근 PDF 사본은 서버로 보내지 않고 이 브라우저의 IndexedDB에만 저장한다. */
(function(root) {
  const database = 'cyviewer-recent-pdfs-v1';
  function transaction(mode, action) {
    return new Promise((resolve, reject) => {
      let blocked = false;
      const request = root.indexedDB.open(database, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('files', {keyPath:'id'});
      request.onerror = () => reject(request.error);
      request.onblocked = () => { blocked = true; reject(new Error('Storage is busy')); };
      request.onsuccess = () => {
        const db = request.result;
        if (blocked) { db.close(); return; }
        db.onversionchange = () => db.close();
        const tx = db.transaction('files', mode);
        let result;
        tx.oncomplete = () => { db.close(); resolve(result); };
        tx.onabort = () => { db.close(); reject(tx.error || new Error('Storage transaction failed')); };
        try { action(tx.objectStore('files'), value => { result = value; }); }
        catch (error) { tx.abort(); }
      };
    });
  }
  const ordered = rows => rows.sort((a,b) => b.openedAt-a.openedAt).slice(0,5);
  root.cyRecentList = () => transaction('readonly', (store, done) => {
    store.getAll().onsuccess = event => done(JSON.stringify(ordered(event.target.result).map(({id,name,openedAt}) => ({id,name,openedAt}))));
  });
  root.cyRecentSave = async (name, bytes) => {
    const copy = new Uint8Array(bytes).slice();
    const digest = await root.crypto.subtle.digest('SHA-256', copy);
    const id = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2,'0')).join('');
    return transaction('readwrite', (store, done) => {
      store.getAll().onsuccess = event => {
        try {
        const rows = event.target.result;
        const openedAt = Math.max(Date.now(), ...rows.map(row => row.openedAt + 1));
        const record = {id,name,openedAt,bytes:copy};
        const keep = ordered([record, ...rows.filter(row => row.id !== id)]);
        store.put(record);
        for (const row of rows) if (!keep.some(item => item.id === row.id)) store.delete(row.id);
        done(id);
        } catch (_) { store.transaction.abort(); }
      };
    });
  };
  root.cyRecentRead = id => transaction('readonly', (store, done) => {
    store.get(id).onsuccess = event => done(event.target.result?.bytes || null);
  });
  root.cyRecentRemove = id => transaction('readwrite', store => { store.delete(id); });
})(globalThis);
