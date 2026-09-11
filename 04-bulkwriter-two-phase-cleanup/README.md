# 04. 만료 일기 자동 정리 — BulkWriter 2-phase

## 문제

Cloud Scheduler 로 매일 만료 일기를 archive 로 이관 후 원본을 삭제하는 Cloud Function 이
60초 timeout 에 걸렸습니다.

원인을 파보니 `BulkWriter` 의 `.set(ref).then(() => writer.delete(ref))` 체인 방식이
`flush()` 를 호출해도 끝나지 않고 hang 하는 경우가 있었습니다. `flush()` 는 **호출
시점까지 큐에 들어온 작업만** 기다리는 시멘틱인데, `.then()` 안에서 새로 enqueue 한
delete 는 그 flush 대상에 포함되지 않기 때문입니다.

## 해결

BulkWriter 소스를 직접 확인해 시멘틱을 파악한 뒤, 로직을 2단계로 분리했습니다.

- **Phase 1**: archive 대상은 `set()`, archive 불필요한 건 바로 `delete()` — 전부
  큐에 넣고 한 번에 `flush()`.
- **Phase 2**: Phase 1 의 archive `set()` 이 성공한 것만 골라 원본 `delete()` 를
  큐에 넣고 다시 `flush()`.

archive 성공이 확인된 것만 원본을 지우므로 데이터 유실 위험 없이, `flush()` 시멘틱과도
맞게 동작합니다. 한 배치(최대 500건)에서 진전이 하나도 없으면(`batchProgress === 0`)
같은 문서를 무한 재처리하지 않도록 중단하는 안전장치도 넣었습니다.

## 코드

[`journals_cleanup.js`](./journals_cleanup.js) — `processExpiredPublicJournalEntries()`
전체 발췌.
