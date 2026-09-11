import 'package:country_picker/country_picker.dart';
import 'package:flutter/widgets.dart';

import 'app_supported_locale.dart';

/// 국가 표시용 sentinel. AI 계정 등 특정 국가에 매핑하지 않고 "viewer 에
/// 맞는 국가로 대체하라" 를 의미. 저장된 code 가 이 값이면 표시 시점에
/// [effectiveCountryCode] 규칙으로 치환.
const kFallbackToViewerCountryCode = 'WORLD';

/// 저장된 country code 를 표시용 code 로 정규화.
///
/// - 일반 code → 그대로.
/// - 'WORLD' sentinel:
///   - viewer 국가의 주 언어가 앱 지원 언어에 있으면 → viewer 국가.
///   - 없으면 → 현재 활성 앱 로케일의 대표 국가 (en → US, ko → KR).
///
/// 빈/null code → null.
String? effectiveCountryCode(
  BuildContext context,
  String? code, {
  String? viewerCountryCode,
}) {
  if (code == null || code.isEmpty) return null;
  if (code.toUpperCase() != kFallbackToViewerCountryCode) return code;

  final vc = viewerCountryCode?.trim().toUpperCase();
  if (vc != null && vc.isNotEmpty && isCountryPrimaryLanguageSupported(vc)) {
    return vc;
  }
  return canonicalCountryForActiveLocale(context);
}

String? localizedCountryName(BuildContext context, String countryCode) {
  final trimmedCode = countryCode.trim();
  if (trimmedCode.isEmpty) {
    return null;
  }

  final localized = CountryLocalizations.of(
    context,
  )?.countryName(countryCode: trimmedCode);
  if (localized != null && localized.trim().isNotEmpty) {
    return localized.trim();
  }

  final parsedCountry = CountryParser.tryParseCountryCode(trimmedCode);
  if (parsedCountry != null && parsedCountry.name.trim().isNotEmpty) {
    return parsedCountry.name.trim();
  }
  return null;
}

String? localizedCountryLabel(
  BuildContext context,
  String countryCode, {
  bool includeFlagEmoji = false,
}) {
  final name = localizedCountryName(context, countryCode);
  if (name == null || name.isEmpty) {
    return null;
  }

  if (!includeFlagEmoji) {
    return name;
  }

  final flagEmoji = CountryParser.tryParseCountryCode(countryCode)?.flagEmoji;
  if (flagEmoji == null || flagEmoji.isEmpty) {
    return name;
  }
  return '$flagEmoji $name';
}
