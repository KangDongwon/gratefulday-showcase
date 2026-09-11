// 부분 발췌본입니다. 원본 functions/journals.js 는 일기 작성/수정/삭제
// Cloud Function 전체를 담고 있으며, 이 쇼케이스와 무관한 부분은 뺐습니다.
// require 경로도 원본 레포 기준이라 이 파일만으로는 실행되지 않습니다.
//
// 여기 남긴 두 가지:
//   1. 만료 일기 정리 — BulkWriter 2-phase (flush 시멘틱 문제 해결)
//   2. 오늘 일기 수정 CF — "오늘" 판정을 서버 시계로만 수행

// ---------------------------------------------------------------------
// 1. 만료 entry 보관/삭제 — BulkWriter 2-phase
// ---------------------------------------------------------------------
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

// ---------------------------------------------------------------------
// 2. 오늘 일기 수정 — "오늘" 판정은 항상 서버 시계로
// ---------------------------------------------------------------------
exports.updateOwnTodayJournalEntry = onCall(
  { region: "asia-northeast3", enforceAppCheck: true },
  withFunctionLogging("updateOwnTodayJournalEntry", async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;

    // "오늘" 의 기준은 클라가 보낸 값이 아니라 항상 CF 자신의 서버 시계.
    const now = new Date();
    const entryId = buildJournalEntryId(uid, now);
    const entryRef = db.collection(collections.publicJournalEntries).doc(entryId);
    const userPrivateRef = db.collection(collections.userPrivate).doc(uid);

    await db.runTransaction(async (tx) => {
      const [entrySnap, privSnap] = await Promise.all([
        tx.get(entryRef),
        tx.get(userPrivateRef),
      ]);
      if (!entrySnap.exists) {
        throw new HttpsError("not-found", "Today journal entry does not exist.");
      }

      // 서버 시계 기준 "오늘 이미 수정했는지" 판정 — 클라 시계 조작 불가.
      const lastRewrittenAt = dateFromTimestamp(
        privSnap.exists ? privSnap.data()?.lastJournalRewrittenAt : null,
      );
      if (lastRewrittenAt && sameUtcCalendarDay(lastRewrittenAt, now)) {
        throw new HttpsError("failed-precondition", "Already rewritten today.", {
          code: "already_rewritten_today",
        });
      }

      tx.set(entryRef, {
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      tx.set(userPrivateRef, {
        lastJournalRewrittenAt: admin.firestore.Timestamp.fromDate(now),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    // ... 인덱스 patch, 응답 반환 (생략)
  }),
);
