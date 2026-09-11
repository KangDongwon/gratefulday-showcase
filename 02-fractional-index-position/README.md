# 02. 로컬 인덱스 순서 유지 — 본인 작성 mid 삽입

## 문제

- 인덱스가 refresh 될 때마다 이미 본 카드들의 순서가 뒤집히면 사용자가 스크롤 방향
  감각을 잃습니다.
- 본인이 방금 쓴 일기는 "지금 보던 위치 바로 뒤" 에 자연스럽게 끼어들어야 합니다.
  맨 앞이나 맨 뒤로 튀면 이질감이 큽니다.

## 해결

- 로컬 인덱스 정렬 키를 **fractional (double)** 로 설계. 본인 작성 시 앞/뒤 항목
  position 값의 중간값을 계산해 O(1) 로 mid 삽입 — 다른 행을 shift 할 필요가 없습니다.
- 삽입 기준점은 "마지막으로 본 entry (`lastViewedEntryId`)" — 그 바로 다음 위치에
  새 글을 꽂고, 새 글 자체도 자동으로 "읽음" 처리해 다음 refresh 때도 위치가 유지되게
  합니다.

## 코드

[`self_write_index_position.dart`](./self_write_index_position.dart)

- `_computeSelfWriteIndexPosition()` — lastViewed 다음 위치의 fractional 값을 계산.
  - lastViewed 없음/사라짐 → 맨 앞 (`min - 1`)
  - lastViewed 가 마지막 → 맨 뒤 (`max + 1`)
  - 중간 → `(viewedPos + nextPos) / 2`
- 오늘 일기 최초 저장(`submitTodayEntry`) 흐름에서 이 값을 바로 drift 인덱스에
  upsert 하는 부분까지 함께 발췌했습니다.
