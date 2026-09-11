# 03. 캐시 staleness 판정 신호

## 문제

관리자가 AI 프로필/일기를 수정하거나, 본인이 다른 기기에서 수정해도 유저 로컬 캐시가
그대로면 옛 내용이 계속 노출됩니다. 그렇다고 매번 서버에서 다시 받아오면 [01](../01-firestore-read-cost)
에서 줄인 읽기 비용이 다시 늘어납니다.

## 해결

- 인덱스 문서의 각 entry 항목에 `updatedAt` 을 함께 저장 (서버가 patch 할 때마다 stamp).
- 클라는 로컬 캐시 row 의 `cachedAt` 과 인덱스의 `updatedAt` 을 비교해서, entry 단위로
  개별 staleness 를 판정 — 인덱스가 더 최신이면 그 entry 만 Firestore 재조회.
- 인덱스에는 있는데 본문 문서가 없으면 (만료/삭제) 로컬 인덱스에서도 정리.

## 코드

[`journal_cached_first_fetch.dart`](./journal_cached_first_fetch.dart)

- `fetchPublicEntryCachedFirst()` — 단건 조회, staleness 비교 후 필요 시에만 재조회.
- `fetchPublicEntriesCachedFirst()` — 다건 조회의 벌크 버전. 캐시 히트/미스/stale 을
  한 번에 판정해 필요한 것만 모아 재조회.

인덱스 쪽에서 `updatedAt` 을 언제·어떻게 stamp 하는지는 [08](../08-admin-edit-instant-sync) 에서
같은 메커니즘을 다룹니다.
