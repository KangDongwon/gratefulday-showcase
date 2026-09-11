# 05. Realtime Database Presence — 유령 카운트

## 문제

감사 나눔 피드에 현재 접속자 수를 보여주는데, 개발 중 hot restart 를 반복하면 count 가
계속 누적되는 "유령 카운트" 현상이 있었습니다.

## 원인

세션 자체는 `sessionRef.onDisconnect().remove()` 로 연결이 끊기면 self-heal 됩니다.
하지만 count 증분은 `onDisconnect().set(ServerValue.increment(-1))` 로 등록했는데,
이 operation 이 서버에서 기대한 대로 감소로 평가되지 않고 사실상 no-op 처리되는
케이스가 있어 세션은 정리돼도 count 만 계속 남는 상황이 생겼습니다.

## 해결

- 디버그 빌드에서만: 새 세션을 write 하기 전에, count 를 `sessions` 노드의 실제 자식
  개수로 강제 동기화 — 세션 자체는 정확하므로 이 값을 신뢰 기준으로 삼아 hot restart
  로 쌓인 유령 카운트를 무력화합니다.
- RTDB presence 경로 자체도 `zDebug_grateful_room` / `grateful_room` 으로 환경을
  분리해, 개발 중 실험이 프로덕션 presence 카운트에 영향을 주지 않게 했습니다.

## 코드

[`presence_session.dart`](./presence_session.dart) — 세션 등록/해제/count watch
전체 발췌.
