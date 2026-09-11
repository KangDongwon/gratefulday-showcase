// 발췌: lib/app/services/journal_service.dart
// (import 경로 등은 원본 레포 기준이라 그대로 컴파일되지 않습니다.)

/// 단건 조회 — drift 캐시 우선, 인덱스의 updatedAt 이 더 신선하면 stale 로
/// 보고 Firestore 재조회.
Future<JournalEntry?> fetchPublicEntryCachedFirst({
  required String entryId,
}) async {
  try {
    final row = await _db.journalEntriesDao.findById(entryId);
    if (row != null) {
      // 인덱스의 updatedAt 이 더 신선하면 캐시 stale → Firestore 재 fetch.
      final indexRow = await _db.publicJournalIndexesDao.findByEntryId(
        entryId,
      );
      final indexUpdatedAt = indexRow?.updatedAt;
      final stale =
          indexUpdatedAt != null && indexUpdatedAt.isAfter(row.cachedAt);
      if (!stale) return journalEntryFromRow(row);
    }
  } catch (error, stackTrace) {
    debugPrint(
      'JournalService.fetchPublicEntryCachedFirst: cache read failed for $entryId: $error',
    );
    debugPrintStack(stackTrace: stackTrace);
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

  // 1. drift 캐시 + 인덱스 staleness 정보 한 번에.
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

  // 2. Firestore whereIn — chunk 30 (Firestore limit) 으로 병렬 fetch.
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
    final receivedIds = <String>{};
    for (final snap in snapshots) {
      for (final doc in snap.docs) {
        final entry = JournalEntry.fromFirestore(doc);
        fetched.add(entry);
        result[doc.id] = entry;
        receivedIds.add(doc.id);
      }
    }
    // 못 받은 id (인덱스에는 있었지만 본문이 사라진 것) 는 null.
    for (final id in needsFetch) {
      result.putIfAbsent(id, () => null);
    }

    // 3. drift 캐시에 일괄 upsert.
    if (fetched.isNotEmpty) {
      await _db.journalEntriesDao.upsertAll(
        fetched.map(journalCompanionFromEntry),
      );
    }
  }

  return entryIds.map((id) => result[id]).toList(growable: false);
}
