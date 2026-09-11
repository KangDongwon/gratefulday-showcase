# 08. 관리자 편집 → 클라 캐시 즉시 반영

## 문제

관리자 페이지에서 AI 계정 일기를 수정해도, 인덱스 문서 자체를 그대로 두면 [03](../03-cache-staleness-signal)
의 staleness 비교가 눈치챌 방법이 없습니다. 반대로 인덱스 문서를 "그냥 다시 통째로
받아오게" 하면 [01](../01-firestore-read-cost) 에서 줄인 읽기 비용이 다시 늘어납니다.

## 해결

- 인덱스 문서는 `app_config/{indexDocId}` 아래 하나의 array 필드로 관리합니다.
  Firestore 트랜잭션으로 read-modify-write 해서 동시성 문제를 피합니다.
- entry 하나를 patch 할 때마다 그 항목의 `updatedAt` 을 서버 시계로 stamp 합니다.
  (array 안이라 `serverTimestamp()` sentinel 은 못 쓰기 때문에 `Timestamp.now()` 사용)
- 관리자 편집 CF 는 이 `patchEntryInPublicIndex()` 를 호출하기만 하면 되고, 클라는
  [03](../03-cache-staleness-signal) 의 비교 로직을 그대로 재사용해 다음에 그 entry 를
  열 때 자동으로 재조회합니다. 별도의 "무효화 알림" 채널을 따로 만들 필요가 없습니다.

## 코드

[`patch_entry_in_public_index.js`](./patch_entry_in_public_index.js) — 인덱스 array
의 read-modify-write 공통 유틸(`withPublicIndexArray`)과, entry 하나를 patch 하며
`updatedAt` 을 stamp 하는 `patchEntryInPublicIndex()`.
