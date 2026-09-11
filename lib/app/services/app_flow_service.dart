// 부분 발췌본입니다. 원본 lib/app/services/app_flow_service.dart 는 로그인
// 상태에 따른 초기 라우팅 전반을 다루며, 이 쇼케이스와 무관한 부분은 뺐습니다.
// import 경로도 원본 레포 기준이라 이 파일만으로는 컴파일되지 않습니다.
//
// 여기 남긴 것: 서버 시간 기준으로 기기 시계를 검증하는 부분. 일기 공개
// 만료 · 하루 1회 작성 제한처럼 "오늘"을 기준으로 하는 규칙은 전부 서버
// 시계로만 판정하고, 클라는 부팅 시 자기 시계가 서버와 너무 벌어져 있지
// 않은지만 확인해 사용자에게 안내한다.

class DeviceTimeMismatchException implements Exception {
  const DeviceTimeMismatchException();

  @override
  String toString() => 'DeviceTimeMismatchException()';
}

static const Duration _deviceTimeTolerance = Duration(minutes: 5);

Future<AuthFlowState> resolveInitialFlowState() async {
  final user = await _authService.reloadCurrentUser();
  if (user == null) return AuthFlowState.signedOut;

  final sessionId = await _userSessionService.ensureCurrentSession(
    uid: user.uid,
  );
  // 세션 문서에 서버가 stamp 한 시각을 읽어와 기기 시계와 비교할 기준으로 사용.
  final serverNow = await _userSessionService.loadSessionServerUpdatedAt(
    uid: user.uid,
    sessionId: sessionId,
  );
  _verifyDeviceTimeAgainstServer(serverNow);

  // ... 이후 프로필 상태에 따른 분기 (생략)
}

void _verifyDeviceTimeAgainstServer(DateTime serverNow) {
  final difference = DateTime.now().difference(serverNow).abs();
  if (difference > _deviceTimeTolerance) {
    throw const DeviceTimeMismatchException();
  }
}
