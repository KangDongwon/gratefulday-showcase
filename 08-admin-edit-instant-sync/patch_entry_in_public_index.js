// 발췌: functions/public_journal_index.js
// (require 경로 등은 원본 레포 기준이라 그대로 실행되지 않습니다.)

// app_config/{indexDocId} 의 array 필드를 read-modify-write 하는 공통 트랜잭션
// 패턴. mutate 가 다음 list 를 반환하면 tx.set, null/undefined 반환하면 skip.
// list 는 항상 fresh copy 로 넘어가므로 안에서 in-place mutate 후 반환 가능.
async function withPublicIndexArray(indexDocId, mutate) {
  const ref = db.collection("app_config").doc(indexDocId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? (snap.data() ?? {}) : {};
    const list = Array.isArray(current[PUBLIC_JOURNAL_INDEX_ARRAY_FIELD])
      ? [...current[PUBLIC_JOURNAL_INDEX_ARRAY_FIELD]]
      : [];
    const next = mutate(list);
    if (next === null || next === undefined) return;
    tx.set(
      ref,
      { [PUBLIC_JOURNAL_INDEX_ARRAY_FIELD]: next },
      { merge: true },
    );
  });
}

// 기존 인덱스 entry 의 필드만 patch + updatedAt stamp. entry 가 인덱스에 없으면
// no-op (상위 노출 범위 밖이라 애초에 인덱싱 안 됐을 수 있음).
async function patchEntryInPublicIndex({
  indexDocId,
  entryId,
  contentLength,
  visibleUntil,
}) {
  let stampedUpdatedAt = null;
  await withPublicIndexArray(indexDocId, (list) => {
    const idx = list.findIndex((it) => it && it.entryId === entryId);
    if (idx < 0) return null;
    const existing = list[idx] ?? {};
    const resolvedContentLength = contentLength !== undefined
      ? Number(contentLength ?? 0)
      : existing.contentLength;
    const resolvedVisibleUntil = visibleUntil !== undefined
      ? visibleUntil
      : existing.visibleUntil;
    // 배열 안에서는 serverTimestamp() sentinel 사용 불가 → 호출 시점의
    // 서버 clock 값을 직접 읽어 stamp. 클라는 이 값을 로컬 cachedAt 과
    // 비교해 staleness 를 판정한다 (03 참고).
    const updatedAt = admin.firestore.Timestamp.now();
    const patched = {
      ...existing,
      updatedAt,
      contentLength: resolvedContentLength,
      visibleUntil: resolvedVisibleUntil,
    };
    list[idx] = patched;
    stampedUpdatedAt = updatedAt;
    return list;
  });
  return { updatedAt: stampedUpdatedAt };
}

module.exports = { withPublicIndexArray, patchEntryInPublicIndex };
