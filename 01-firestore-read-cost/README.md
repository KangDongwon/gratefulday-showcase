# 01. Firestore 읽기 비용 최적화

## 문제

공개 일기를 컬렉션 쿼리로 직접 조회하면 유저 수 · 일기 수에 비례해 Firestore 읽기 비용이
지속적으로 증가합니다. 감사 나눔 피드처럼 자주 열리는 화면에서는 특히 부담이 큽니다.

## 해결

- 서버가 별도 **인덱스 문서** (`app_config/public_journal_indexes`) 를 관리 — 현재 공개 중인
  일기 목록만 `{entryId, contentLength, visibleUntil, updatedAt}` 형태로 축약 저장.
- 클라는 이 인덱스 문서 하나만 TTL(1시간) 기준으로 pull. 개별 일기 본문은 로컬 캐시
  우선 조회, 캐시 미스일 때만 Firestore 개별 read.
- Drift(SQLite) 로 인덱스를 write-through 캐시하고, 재실행/재접속 시에도 그대로 사용.

## 코드

[`public_journal_index_service.dart`](./public_journal_index_service.dart)

- `ensureCached()` — drift 캐시가 비어있거나 TTL 초과일 때만 Firestore 인덱스 문서를
  1회 fetch, 통째로 drift 에 교체.
- `_mergeOrdered()` — 이미 본 순서(read)는 유지하고, 새 인덱스에만 있는 항목(unread)을
  뒤에 이어 붙이는 병합 로직. (자세한 이유는 [02](../02-fractional-index-position) 참고)
