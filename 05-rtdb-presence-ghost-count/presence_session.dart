// 발췌: lib/app/services/gratitude_sharing_service.dart
// (import 경로, 클래스 선언부 등은 원본 레포 기준이라 그대로 컴파일되지 않습니다.)

// debug 빌드는 zDebug_grateful_room 하위로 격리 — prod 유저 presence 와 섞이지 않도록.
static const _roomNode = kDebugMode
    ? 'zDebug_grateful_room'
    : 'grateful_room';

DatabaseReference get _sessionsRef =>
    _database.ref('presence/$_roomNode/sessions');
DatabaseReference get _presenceCountRef =>
    _database.ref('presence/$_roomNode/count');

String? _sessionId;
String? _sessionUid;

Future<void> ensurePresenceSession({required UserProfile profile}) async {
  if (_sessionId != null && _sessionUid == profile.uid) {
    return;
  }

  final sessionId =
      _sessionsRef.push().key ??
      '${profile.uid}_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
  final sessionRef = _sessionsRef.child(sessionId);
  final payload = <String, Object?>{
    'uid': profile.uid,
    'nickname': profile.nickname,
    'startedAt': ServerValue.timestamp,
  };

  // debug 빌드에선 hot restart 로 반복 호출 시 count 의 onDisconnect.set(increment)
  // 가 서버에서 -1 로 평가되지 않고 no-op 이라 매번 +1 만 남음 (유령 카운트).
  // 세션 자체는 각 sessionRef.onDisconnect().remove() 로 self-heal 되므로
  // sessions 자식 개수는 정확. 새 세션 write 전에 count 를 그 값으로 강제
  // 동기화하면 이후 +1 이 정확히 매칭됨. debug room 은 격리되어 있어 안전.
  if (kDebugMode) {
    final snap = await _sessionsRef.get();
    final actual = snap.value is Map ? (snap.value as Map).length : 0;
    await _presenceCountRef.set(actual);
  }
  await sessionRef.onDisconnect().remove();
  await sessionRef.set(payload);
  // 동접 count 증가 + onDisconnect 시 자동 감소 등록 (앱/네트워크 끊김 대비).
  await _presenceCountRef.onDisconnect().set(ServerValue.increment(-1));
  await _presenceCountRef.set(ServerValue.increment(1));
  _sessionId = sessionId;
  _sessionUid = profile.uid;
}

Future<void> clearPresenceSession() async {
  final sessionId = _sessionId;
  if (sessionId == null || sessionId.isEmpty) {
    _sessionUid = null;
    return;
  }

  final sessionRef = _sessionsRef.child(sessionId);
  try {
    await sessionRef.remove();
    // 명시적 종료 — onDisconnect 취소 후 count 직접 감소 (중복 방지).
    await _presenceCountRef.onDisconnect().cancel();
    await _presenceCountRef.set(ServerValue.increment(-1));
  } finally {
    _sessionId = null;
    _sessionUid = null;
  }
}

Stream<int> watchPresenceCount() {
  return _presenceCountRef.onValue.map((event) {
    final raw = event.snapshot.value;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  });
}
