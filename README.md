# GratefulDay — Code Showcase

GratefulDay (하루감사) 는 하루 한 번 감사일기를 쓰고 다음날까지 나누는 개인 프로젝트입니다.
기획 · UX · Flutter 앱 · Firebase 백엔드 · React 관리자 페이지까지 1인으로 개발했습니다.

실제 서비스 레포는 출시를 앞두고 있어 **비공개**로 운영합니다. 이 레포는 그중 기술적으로
고민하고 해결한 부분을, 실제 레포 디렉토리 구조를 그대로 유지한 채 필요한 코드만 추려서
공유하기 위한 쇼케이스입니다.

## 담긴 내용

| # | 주제 | 코드 |
|---|---|---|
| 1 | Firestore 읽기 비용 최적화 | [`lib/app/services/public_journal_index_service.dart`](./lib/app/services/public_journal_index_service.dart) |
| 2 | 로컬 인덱스 순서 유지 (fractional mid-삽입) | [`lib/app/services/journal_service.dart`](./lib/app/services/journal_service.dart) §1 |
| 3 | 캐시 staleness 판정 | [`lib/app/services/journal_service.dart`](./lib/app/services/journal_service.dart) §2 |
| 4 | 만료 데이터 정리 — BulkWriter 2-phase | [`functions/journals.js`](./functions/journals.js) §1 |
| 5 | RTDB presence 유령 카운트 | [`lib/app/services/gratitude_sharing_service.dart`](./lib/app/services/gratitude_sharing_service.dart) |
| 6 | 서버 시간 기반 정책 | [`lib/app/services/app_flow_service.dart`](./lib/app/services/app_flow_service.dart) (클라) · [`functions/journals.js`](./functions/journals.js) §2 (서버) |
| 7 | 다국어 국가 표시 폴백 | [`lib/app/l10n/country_display.dart`](./lib/app/l10n/country_display.dart) |
| 8 | 관리자 편집 → 클라 즉시 반영 | [`functions/public_journal_index.js`](./functions/public_journal_index.js) |

### 1. Firestore 읽기 비용 최적화

공개 일기를 컬렉션 쿼리로 직접 조회하면 유저 수 · 일기 수에 비례해 읽기 비용이 계속
늘어납니다. 서버가 관리하는 **인덱스 문서** 하나만 TTL 기준으로 pull 하고, 개별 일기
본문은 로컬 캐시 우선 조회하도록 바꿔 이 문제를 풀었습니다.

### 2. 로컬 인덱스 순서 유지

인덱스가 refresh 될 때마다 순서가 뒤집히면 사용자가 스크롤 방향 감각을 잃습니다.
정렬 키를 **fractional (double)** 로 설계해서, 본인이 방금 쓴 글을 "마지막으로 본
위치 바로 뒤" 에 O(1) 로 mid-삽입합니다.

### 3. 캐시 staleness 판정

관리자나 본인이 다른 기기에서 수정해도 로컬 캐시가 stale 하면 옛 내용이 보입니다.
인덱스 항목에 `updatedAt` 을 같이 두고, 로컬 `cachedAt` 과 비교해서 entry 단위로만
필요한 만큼 재조회합니다.

### 4. 만료 데이터 정리 — BulkWriter 2-phase

Cloud Scheduler 로 만료 일기를 정리하는 CF 가 60초 timeout 에 걸렸습니다. 원인은
BulkWriter 의 `flush()` 가 호출 시점 이전 큐만 기다리는 시멘틱이라, `.set().then(delete)`
체인이 hang 하는 것. archive `set` 과 원본 `delete` 를 2단계로 분리해 해결했습니다.

### 5. RTDB presence 유령 카운트

개발 중 hot restart 를 반복하면 동접자 카운트가 계속 누적되는 문제가 있었습니다.
`onDisconnect().set(increment(-1))` 이 기대와 다르게 no-op 되는 케이스를 발견하고,
디버그 빌드에서 세션 수를 기준으로 카운트를 강제 재동기화해 해결했습니다.

### 6. 서버 시간 기반 정책

"오늘" 을 기준으로 하는 규칙(공개 만료, 일 1회 작성 제한 등)은 전부 서버 시계로만
판정합니다. 클라는 부팅 시 자기 시계가 서버와 5분 이상 벌어지면 안내만 띄웁니다.

### 7. 다국어 국가 표시 폴백

AI 페르소나처럼 국가를 고정하고 싶지 않은 계정엔 `WORLD` sentinel 을 부여하고,
표시 시점에 viewer 로케일에 맞는 국가로 자동 매핑합니다.

### 8. 관리자 편집 → 클라 즉시 반영

관리자가 AI 일기를 수정하면 인덱스 항목의 `updatedAt` 만 다시 stamp 합니다. 별도의
"무효화 알림" 채널 없이, 클라가 이미 갖고 있는 staleness 비교 로직(§3) 이 그대로
재사용되어 다음에 그 entry 를 열 때 자동 재조회합니다.

## 참고

- 여기 담긴 코드는 실제 프로덕션 레포에서 **발췌**한 것으로, 그대로 컴파일/실행되지 않습니다
  (import 경로, 주변 클래스, 무관한 함수 등은 생략). 디렉토리 경로는 실제 레포와 동일합니다.
- 시크릿 값, Firestore 보안 규칙 세부 조건, 결제 검증 로직 등 민감한 부분은 포함하지 않았습니다.
- 스택: Flutter · Dart · Riverpod · Drift (SQLite) / Firebase (Firestore · Cloud Functions v2 · Realtime Database) / React · TypeScript (관리자 페이지)
