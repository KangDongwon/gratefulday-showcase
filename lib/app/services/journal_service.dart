// 부분 발췌본입니다. 원본 lib/app/services/journal_service.dart 는 이보다
// 훨씬 크고(작성/수정/삭제/조회 등 JournalService 전체 구현) 이 쇼케이스와
// 무관한 부분은 뺐습니다. import 경로도 원본 레포 기준이라 이 파일만으로는
// 컴파일되지 않습니다.
//
// 여기 남긴 두 가지:
//   1. 본인 작성 글을 로컬 인덱스에 fractional position 으로 mid-삽입
//   2. 공개 일기 캐시 우선 조회 + 인덱스 updatedAt 기반 staleness 판정

// ---------------------------------------------------------------------
// 1. 로컬 인덱스 순서 유지 — 본인 작성 mid 삽입
// ---------------------------------------------------------------------

// 오늘 일기 최초 저장(submitTodayEntry) 흐름 중 인덱스 삽입 부분.
//
// 인덱스 캐시에 mid-position 삽입 — lastViewedEntryId 바로 다음 위치에
// 오도록 fractional position 계산. 그리고 새 entry 를 자동 "읽음"
// 처리 (lastViewedEntryId = new.id). 다음 refresh 때 인덱스 서비스의
// 병합 로직이 이 순서를 유지.
Future<void> _insertOwnEntryIntoIndex(JournalEntry entry) async {
  final targetPos = await _computeSelfWriteIndexPosition(entry.id);
  final syncedAt =
      await _db.publicJournalIndexesDao.latestCachedAt() ??
      DateTime.fromMillisecondsSinceEpoch(0);
  await _db.publicJournalIndexesDao.upsert(
    PublicJournalIndexesCompanion(
      entryId: Value(entry.id),
      contentLength: Value(entry.contentLength),
      visibleUntil: Value(entry.visibleUntil),
      // cachedAt 은 "서버 인덱스와 마지막으로 동기화된 시점" 의미로 사용됨
      // (ensureCached 의 1시간 TTL 판정 기준). 본인 write 로 인해 이 값이
      // now 로 튀면 다른 유저/admin 변경분 감지가 1시간 지연됨 → 기존
      // MAX(cachedAt) 을 유지해 TTL timer 리셋 방지.
      cachedAt: Value(syncedAt),
      position: Value(targetPos),
    ),
  );
  await _lastViewed.save(entry.id);
}

/// 본인이 방금 작성한 [newEntryId] 를 인덱스 어느 position 에 넣을지 결정.
/// - lastViewedEntryId 가 인덱스에 있으면 → 그 다음 위치 (viewed + next) / 2.
/// - lastViewedEntryId 가 없거나 인덱스에 없으면 → 인덱스 최소값 - 1 (맨 앞).
/// - 인덱스가 비었으면 → 0.0.
Future<double> _computeSelfWriteIndexPosition(String newEntryId) async {
  final rows = await _db.publicJournalIndexesDao.all();
  if (rows.isEmpty) return 0.0;
  final lastViewedEntryId = await _lastViewed.load();
  if (lastViewedEntryId == null) {
    // 아무것도 안 봤음 → 맨 앞.
    return rows.first.position - 1;
  }
  final viewedIdx = rows.indexWhere((r) => r.entryId == lastViewedEntryId);
  if (viewedIdx < 0) {
    // 저장된 lastViewed 가 현재 인덱스에 없음 → 맨 앞.
    return rows.first.position - 1;
  }
  final viewedPos = rows[viewedIdx].position;
  if (viewedIdx + 1 >= rows.length) {
    // lastViewed 가 마지막 → 그 뒤에 append.
    return viewedPos + 1;
  }
  final nextPos = rows[viewedIdx + 1].position;
  return (viewedPos + nextPos) / 2;
}

// ---------------------------------------------------------------------
// 2. 캐시 staleness 판정 — 인덱스 updatedAt vs 로컬 cachedAt
// ---------------------------------------------------------------------

/// 단건 조회 — drift 캐시 우선, 인덱스의 updatedAt 이 더 신선하면 stale 로
/// 보고 Firestore 재조회.
Future<JournalEntry?> fetchPublicEntryCachedFirst({
  required String entryId,
}) async {
  final row = await _db.journalEntriesDao.findById(entryId);
  if (row != null) {
    // 인덱스의 updatedAt 이 더 신선하면 캐시 stale → Firestore 재 fetch.
    final indexRow = await _db.publicJournalIndexesDao.findByEntryId(entryId);
    final indexUpdatedAt = indexRow?.updatedAt;
    final stale =
        indexUpdatedAt != null && indexUpdatedAt.isAfter(row.cachedAt);
    if (!stale) return journalEntryFromRow(row);
  }

  final snapshot = await _firestore
      .collection(FirestorePaths.publicJournalEntriesCollection)
      .doc(entryId)
      .get();
  if (!snapshot.exists) {
    // 인덱스에는 있는데 본문이 없음 → 만료/삭제 된 stale 항목. 로컬 인덱스에서 제거.
    await _db.publicJournalIndexesDao.deleteById(entryId);
    return null;
  }
  final entry = JournalEntry.fromFirestore(snapshot);
  await _db.journalEntriesDao.upsert(journalCompanionFromEntry(entry));
  return entry;
}

/// 다건 조회 벌크 버전 — 캐시 히트/미스/stale 을 한 번에 판정해 필요한 것만
/// Firestore whereIn 으로 모아 재조회 (30개씩 chunk, Firestore whereIn 제한).
Future<List<JournalEntry?>> fetchPublicEntriesCachedFirst({
  required List<String> entryIds,
}) async {
  if (entryIds.isEmpty) return const <JournalEntry?>[];

  final result = <String, JournalEntry?>{};
  final needsFetch = <String>[];

  final cachedRows = await _db.journalEntriesDao.findByIds(entryIds);
  final indexRows = await _db.publicJournalIndexesDao.findByEntryIds(
    entryIds,
  );
  final cachedById = {for (final r in cachedRows) r.id: r};
  final indexById = {for (final r in indexRows) r.entryId: r};

  for (final id in entryIds) {
    final row = cachedById[id];
    if (row == null) {
      needsFetch.add(id);
      continue;
    }
    final indexUpdatedAt = indexById[id]?.updatedAt;
    final stale =
        indexUpdatedAt != null && indexUpdatedAt.isAfter(row.cachedAt);
    if (stale) {
      needsFetch.add(id);
    } else {
      result[id] = journalEntryFromRow(row);
    }
  }

  if (needsFetch.isNotEmpty) {
    const chunkSize = 30;
    final chunks = <List<String>>[
      for (var i = 0; i < needsFetch.length; i += chunkSize)
        needsFetch.sublist(i, (i + chunkSize).clamp(0, needsFetch.length)),
    ];
    final snapshots = await Future.wait(
      chunks.map(
        (chunk) => _firestore
            .collection(FirestorePaths.publicJournalEntriesCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );

    final fetched = <JournalEntry>[];
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final entry = JournalEntry.fromFirestore(doc);
        fetched.add(entry);
        result[doc.id] = entry;
      }
    }
    for (final id in needsFetch) {
      result.putIfAbsent(id, () => null);
    }
    if (fetched.isNotEmpty) {
      await _db.journalEntriesDao.upsertAll(
        fetched.map(journalCompanionFromEntry),
      );
    }
  }

  return entryIds.map((id) => result[id]).toList(growable: false);
}
