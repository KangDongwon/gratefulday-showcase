// 발췌: functions/journals.js
// (require 경로 등은 원본 레포 기준이라 그대로 실행되지 않습니다.)

// ---------- 만료 entry 보관/삭제 ----------
async function processExpiredPublicJournalEntries({ useDebugCollections }) {
  const collections = appCollections(useDebugCollections);
  const now = new Date();
  const nowTimestamp = admin.firestore.Timestamp.fromDate(now);
  const writer = db.bulkWriter();
  const stats = {
    archived: 0,
    archiveFailed: 0,
    deleted: 0,
    deleteFailed: 0,
    skippedNoAuthor: 0,
  };
  let aborted = false;

  try {
    while (true) {
      const snapshot = await db.collection(collections.publicJournalEntries)
        .where("visibleUntil", "<=", nowTimestamp)
        .limit(500)
        .get();
      if (snapshot.empty) break;

      // bulkWriter 의 flush 시멘틱 (`flush()` 는 호출 시점 이전 큐만 await)
      // 때문에 set→.then→delete 체인은 hang. 2-phase 로 분리:
      //   Phase 1: archive set + direct delete 모두 queue → flush
      //   Phase 2: 성공한 archive 의 source delete queue → flush
      // 이로써 archive 안전성 (set 성공해야만 source delete) 유지하면서
      // bulkWriter 와 호환.
      let batchProgress = 0;
      const archiveCandidates = []; // {entryDoc, setPromise}
      const directDeletePromises = [];

      for (const entryDoc of snapshot.docs) {
        const entryData = entryDoc.data() || {};
        const isAiEntry = entryData.isAI === true;
        // AI 일기는 항상 users 하위로 보관. 일반 계정은 일기의 shouldArchive
        // 플래그가 true 일 때만 user_private 하위로 보관.
        const shouldArchive = isAiEntry || entryData.shouldArchive === true;
        const authorUid = `${entryData.authUid ?? ""}`.trim();

        if (shouldArchive && authorUid) {
          const destRef = userArchiveJournalEntriesRef(collections, {
            uid: authorUid,
            isAi: isAiEntry,
          }).doc(entryDoc.id);
          archiveCandidates.push({
            entryDoc,
            setPromise: writer.set(destRef, {
              ...entryData,
              id: entryData.id ?? entryDoc.id,
              isArchived: true,
              archivedAt: entryData.archivedAt ?? admin.firestore.Timestamp.fromDate(now),
              deletedFromPublicAt: admin.firestore.Timestamp.fromDate(now),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true }),
          });
        } else {
          if (shouldArchive) stats.skippedNoAuthor++;
          // shouldArchive 인데 authUid 없는 케이스도 그대로 삭제 (원본 동작 유지).
          directDeletePromises.push(
            writer.delete(entryDoc.ref).then(
              () => {
                stats.deleted++;
                batchProgress++;
              },
              () => {
                stats.deleteFailed++;
              },
            ),
          );
        }
      }

      await writer.flush();
      await Promise.allSettled(directDeletePromises);

      // Phase 2: archive set 결과 settle 후 성공한 것만 source delete queue.
      const archiveDeletePromises = [];
      for (const { entryDoc, setPromise } of archiveCandidates) {
        try {
          await setPromise;
          stats.archived++;
          archiveDeletePromises.push(
            writer.delete(entryDoc.ref).then(
              () => {
                stats.deleted++;
                batchProgress++;
              },
              () => {
                stats.deleteFailed++;
              },
            ),
          );
        } catch (_) {
          stats.archiveFailed++;
        }
      }

      if (archiveDeletePromises.length > 0) {
        await writer.flush();
        await Promise.allSettled(archiveDeletePromises);
      }

      if (batchProgress === 0) {
        // 한 건도 진전 없음 — 같은 doc 들을 무한히 재 처리하지 않도록 중단.
        aborted = true;
        break;
      }
    }
  } finally {
    await writer.close();
  }

  console.log("[processExpiredPublicJournalEntries] done", {
    useDebugCollections,
    aborted,
    ...stats,
  });
}
