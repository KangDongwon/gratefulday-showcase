# 06. 서버 시간 기반 공개 정책

## 문제

일기 공개 만료, 하루 1회 작성/수정 제한처럼 "오늘" 을 기준으로 하는 규칙이 많습니다.
기기 시간을 신뢰하면 사용자가 기기 시간을 바꿔서 제한을 우회하거나, 반대로 시계가
어긋난 기기에서 억울하게 규칙에 걸릴 수 있습니다.

## 해결

- **판정 자체는 항상 서버에서.** Cloud Functions 는 자신의 서버 시계(`new Date()`)로
  "오늘"을 계산하고, Firestore 쓰기에는 `serverTimestamp()` / `Timestamp.fromDate(now)`
  (서버 now) 를 사용합니다. 클라가 보낸 시각은 판정에 쓰지 않습니다.
- **클라는 부팅 시 자기 시계를 검증.** 세션 문서에 서버가 stamp 한 시각을 읽어와서
  기기 시각과 비교 — 5분 이상 벌어지면 `DeviceTimeMismatchException` 을 던져서 안내
  화면으로 유도합니다. (판정용이 아니라 "사용자 기기 시계가 이상하다" 는 UX 안내 목적)

## 코드

- [`device_time_check.dart`](./device_time_check.dart) — 클라이언트에서 서버-기기
  시간 차이를 검증하는 부분 (`app_flow_service.dart` 발췌).
- [`server_clock_daily_limit.js`](./server_clock_daily_limit.js) — 서버가 자신의
  시계로 "오늘 이미 수정했는지" 를 트랜잭션 안에서 판정하는 부분 (`updateOwnTodayJournalEntry`
  Cloud Function 발췌).
