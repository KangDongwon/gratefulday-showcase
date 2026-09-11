// 발췌: lib/app/services/app_flow_service.dart
// (import 경로, 클래스 선언부 등은 원본 레포 기준이라 그대로 컴파일되지 않습니다.)

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
