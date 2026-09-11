// AI 캐릭터 페르소나 정의 — 식별자 (enum) + viewer 국가별 닉네임/자기소개 lookup.
// 렌더링 (얼굴 그리기) 은 `ai_face_avatar.dart` 가 담당. 이 파일은 데이터.

enum AiStyle {
  /// 국가별 변형이 있는 '아무개' 페르소나. 닉네임/자기소개/외형 색감이
  /// viewer 의 국가 (currentUserProfile.countryCode) 에 따라 결정됨.
  /// 렌더링은 현재 [blob] 과 동일 (인종 논쟁 회피용 중립 스타일로 통합).
  ahmugae,

  /// 미국 시골 소년 (Huckleberry Finn). 고정 — viewer 국가 무관.
  huckleberryFinn,

  /// 인간 형상을 벗어난 중립 캐릭터 — 두부/콩 같은 둥근 몸체 + 심플 표정.
  /// 국가/인종 표시 없음.
  blob,

  /// 이슬방울 캐릭터 — 앱 화폐 dew 와 컨셉 연결. 파랑 톤 + 하이라이트.
  dewDrop,
}

/// Firestore 에 저장된 enum-name 문자열을 AiStyle 로 매핑. 모르거나 빈
/// 문자열이면 null — caller 가 generic fallback (예: 이니셜) 사용.
AiStyle? parseAiStyle(String? value) {
  if (value == null || value.isEmpty) return null;

  for (final v in AiStyle.values) {
    if (v.name == value) return v;
  }
  return null;
}
