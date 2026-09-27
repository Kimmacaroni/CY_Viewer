const {test} = require('node:test');
const assert = require('node:assert/strict');
const {indexedDB, IDBObjectStore} = require('fake-indexeddb');
globalThis.indexedDB = indexedDB;
globalThis.crypto ??= require('node:crypto').webcrypto;
require('../macos_app/web/recent-pdfs.js');
test('브라우저 최근 PDF: 5개 제한, 중복 이동, 재조회, 삭제, 사본 무결성', async () => {
  const ids=[];
  for(let n=0;n<7;n++) ids.push(await cyRecentSave(`문서${n}.pdf`,new Uint8Array([37,80,68,70,n])));
  let rows=JSON.parse(await cyRecentList());
  assert.deepEqual(rows.map(x=>x.name),['문서6.pdf','문서5.pdf','문서4.pdf','문서3.pdf','문서2.pdf']);
  assert.equal(await cyRecentRead(ids[0]),null);
  assert.deepEqual([...await cyRecentRead(ids[3])],[37,80,68,70,3]);
  await cyRecentSave('다시 연 문서.pdf',new Uint8Array([37,80,68,70,3]));
  rows=JSON.parse(await cyRecentList());
  assert.equal(rows.length,5); assert.equal(rows[0].id,ids[3]);
  assert.equal(new Set(rows.map(x=>x.id)).size,5);
  // 새 연결에서 조회해도 같은 사본을 읽고, 제거 후 바이트도 사라진다.
  assert.deepEqual([...await cyRecentRead(rows[0].id)],[37,80,68,70,3]);
  const before = await cyRecentList();
  const originalPut = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = () => { throw new DOMException('quota', 'QuotaExceededError'); };
  try { await assert.rejects(cyRecentSave('실패.pdf',new Uint8Array([99]))); }
  finally { IDBObjectStore.prototype.put = originalPut; }
  assert.equal(await cyRecentList(),before);
  assert.deepEqual([...await cyRecentRead(rows[0].id)],[37,80,68,70,3]);
  await cyRecentRemove(rows[0].id);
  assert.equal(await cyRecentRead(rows[0].id),null);
  assert.equal(JSON.parse(await cyRecentList()).length,4);
});
