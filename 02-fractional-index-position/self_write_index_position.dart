// 발췌: lib/app/services/journal_service.dart
// (import 경로 등은 원본 레포 기준이라 그대로 컴파일되지 않습니다.)

// --- 오늘 일기 최초 저장 흐름 중 인덱스 삽입 부분 ---
//
// 인덱스 캐시에 mid-position 삽입 — lastViewedEntryId 바로 다음 위치에
// 오도록 fractional position 계산. 그리고 새 entry 를 자동 "읽음"
// 처리 (lastViewedEntryId = new.id). 다음 refresh 때 _mergeOrdered 가
// 이 순서를 유지.
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
