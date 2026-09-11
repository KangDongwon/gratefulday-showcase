// 발췌: functions/journals.js (updateOwnTodayJournalEntry)
// (require 경로 등은 원본 레포 기준이라 그대로 실행되지 않습니다.)

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
        content: /* ... */ undefined,
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
