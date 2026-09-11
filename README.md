# GratefulDay — Code Showcase

GratefulDay (하루감사) 는 하루 한 번 감사일기를 쓰고 다음날까지 나누는 개인 프로젝트입니다.
기획 · UX · Flutter 앱 · Firebase 백엔드 · React 관리자 페이지까지 1인으로 개발했습니다.

실제 서비스 레포는 출시를 앞두고 있어 **비공개**로 운영합니다. 이 레포는 그중 기술적으로
고민하고 해결한 부분만 추려서 코드로 공유하기 위한 쇼케이스입니다.

## 담긴 내용

문제를 풀어낸 순서대로 번호를 매겼습니다. 각 폴더의 `README.md` 에 문제 · 해결 · 코드 설명이 있습니다.

| # | 주제 | 핵심 |
|---|---|---|
| [01](./01-firestore-read-cost) | Firestore 읽기 비용 최적화 | 컬렉션 쿼리 대신 서버가 관리하는 인덱스 문서 + 클라 로컬 캐시 |
| [02](./02-fractional-index-position) | 로컬 인덱스 순서 유지 | fractional position 으로 본인 작성 글을 O(1) mid-삽입 |
| [03](./03-cache-staleness-signal) | 캐시 staleness 판정 | 인덱스의 updatedAt 과 로컬 cachedAt 비교로 개별 entry 단위 재조회 |
| [04](./04-bulkwriter-two-phase-cleanup) | 만료 데이터 정리 timeout | BulkWriter flush 시멘틱 문제를 2-phase 로 재설계 |
| [05](./05-rtdb-presence-ghost-count) | RTDB presence 유령 카운트 | onDisconnect 증분 연산 신뢰 못하는 상황의 self-heal |
| [06](./06-server-authoritative-clock) | 서버 시간 기반 정책 | 기기 시간 대신 서버 시간을 신뢰 기준으로 사용 |
| [07](./07-locale-country-fallback) | 다국어 국가 표시 폴백 | sentinel 값으로 viewer 로케일에 맞춰 국가 자동 매핑 |
| [08](./08-admin-edit-instant-sync) | 관리자 편집 → 클라 즉시 반영 | 인덱스 patch 시 updatedAt 을 함께 stamp 해서 staleness 신호로 사용 |

## 참고

- 여기 담긴 코드는 실제 프로덕션 레포에서 **발췌**한 것으로, 그대로 컴파일/실행되지 않습니다
  (import 경로, 주변 클래스, 설정값 등 생략).
- 시크릿 값, Firestore 보안 규칙 세부 조건, 결제 검증 로직 등 민감한 부분은 포함하지 않았습니다.
- 스택: Flutter · Dart · Riverpod · Drift (SQLite) / Firebase (Firestore · Cloud Functions v2 · Realtime Database) / React · TypeScript (관리자 페이지)
