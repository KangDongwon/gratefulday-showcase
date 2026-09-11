import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'ai_persona.dart';

export 'ai_persona.dart' show AiStyle, parseAiStyle;

class AiFaceAvatar extends ConsumerStatefulWidget {
  const AiFaceAvatar({
    super.key,
    required this.size,
    this.style = AiStyle.ahmugae,
  });

  final double size;
  final AiStyle style;

  @override
  ConsumerState<AiFaceAvatar> createState() => _AiFaceAvatarState();
}

class _AiFaceAvatarState extends ConsumerState<AiFaceAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // viewer 의 국가 — amugae 의 외형 분기에 사용. profile 미로딩이면 null.
    final viewerCountryCode = ref
        .watch(currentUserProfileProvider)
        .asData
        ?.value
        ?.countryCode;
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _AiFacePainter(
              phase: _controller.value,
              style: widget.style,
              viewerCountryCode: viewerCountryCode,
            ),
          ),
        ),
      ),
    );
  }
}

class _Palette {
  const _Palette({
    required this.background,
    required this.skin,
    required this.skinShade,
    required this.hair,
    required this.shirt,
    required this.mouth,
  });

  final Color background;
  final Color skin;
  final Color skinShade;
  final Color hair;
  final Color shirt;
  final Color mouth;
}

/// Hand-drawn placeholder avatar for AI authors. [phase] drives a looping
/// expression: periodic blinks and a gentle smile. [style] selects the base
/// character; for `amugae`, [viewerCountryCode] further selects palette.
class _AiFacePainter extends CustomPainter {
  _AiFacePainter({
    required this.phase,
    required this.style,
    required this.viewerCountryCode,
  });

  final double phase;
  final AiStyle style;
  final String? viewerCountryCode;

  static const _huckleberryFinn = _Palette(
    background: Color(0xFFF2E6C7),
    skin: Color(0xFFF2D2B8),
    skinShade: Color(0xFFE0B596),
    hair: Color(0xFFC97F4D),
    shirt: Color(0xFFB97A4F),
    mouth: Color(0xFFB85A4A),
  );

  // Blob — 중립 두부/콩 캐릭터. 크림 톤. 머리/옷 개념 없음.
  static const _blob = _Palette(
    background: Color(0xFFF5EFE4),
    skin: Color(0xFFF1DFC5),
    skinShade: Color(0xFFD8C0A0),
    hair: Color(0xFFB88A55),
    shirt: Color(0xFFEEE2CE),
    mouth: Color(0xFF8B5A2B),
  );

  // DewDrop — 이슬방울. 파랑/청록 톤 + 하이라이트.
  static const _dewDrop = _Palette(
    background: Color(0xFFE6F1F5),
    skin: Color(0xFFB8D8E5),
    skinShade: Color(0xFF7EB8CB),
    hair: Color(0xFF4C8AA8),
    shirt: Color(0xFFCFE4EC),
    mouth: Color(0xFF3D6D85),
  );

  _Palette get _palette {
    switch (style) {
      case AiStyle.ahmugae:
        // ahmugae 는 임시로 blob 시각으로 통합 (인종 논쟁 회피).
        return _blob;
      case AiStyle.huckleberryFinn:
        return _huckleberryFinn;
      case AiStyle.blob:
        return _blob;
      case AiStyle.dewDrop:
        return _dewDrop;
    }
  }

  double get _eyeOpen {
    for (final center in const [0.32, 0.8]) {
      final d = (phase - center).abs();
      if (d < 0.035) {
        return (d / 0.035).clamp(0.0, 1.0);
      }
    }
    return 1.0;
  }

  double get _smile => 0.5 + 0.5 * math.sin(phase * 2 * math.pi);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final palette = _palette;

    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);

    switch (style) {
      case AiStyle.ahmugae:
      case AiStyle.blob:
        _paintBlob(canvas, w, h, palette);
        return;
      case AiStyle.dewDrop:
        _paintDewDrop(canvas, w, h, palette);
        return;
      case AiStyle.huckleberryFinn:
        break; // 아래 사람 형태 그리기로 진행.
    }

    final eyeOpen = _eyeOpen;
    final smile = _smile;
    final browLift = smile * h * 0.014;
    final skinPaint = Paint()..color = palette.skin;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 1.12),
        width: w * 1.15,
        height: h * 0.72,
      ),
      Paint()..color = palette.shirt,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.78),
          width: w * 0.24,
          height: h * 0.2,
        ),
        Radius.circular(w * 0.08),
      ),
      Paint()..color = palette.skinShade,
    );

    canvas.drawCircle(Offset(w * 0.29, h * 0.46), w * 0.055, skinPaint);
    canvas.drawCircle(Offset(w * 0.71, h * 0.46), w * 0.055, skinPaint);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.45),
        width: w * 0.48,
        height: h * 0.58,
      ),
      skinPaint,
    );

    _drawHair(canvas, w, h, palette.hair);

    final browPaint = Paint()
      ..color = palette.hair
      ..strokeWidth = w * 0.028
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(w * 0.36, h * 0.41 - browLift),
      Offset(w * 0.46, h * 0.42 - browLift),
      browPaint,
    );
    canvas.drawLine(
      Offset(w * 0.54, h * 0.42 - browLift),
      Offset(w * 0.64, h * 0.41 - browLift),
      browPaint,
    );

    final pupilPaint = Paint()..color = const Color(0xFF2E2620);
    final eyeHeight = h * 0.055 * eyeOpen;
    for (final ex in const [0.41, 0.59]) {
      final center = Offset(w * ex, h * 0.47);
      if (eyeOpen < 0.15) {
        canvas.drawLine(
          Offset(w * ex - w * 0.05, h * 0.47),
          Offset(w * ex + w * 0.05, h * 0.47),
          Paint()
            ..color = palette.hair
            ..strokeWidth = w * 0.02
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawOval(
          Rect.fromCenter(center: center, width: w * 0.10, height: eyeHeight),
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(center, w * 0.026 * eyeOpen, pupilPaint);
      }
    }

    if (style == AiStyle.huckleberryFinn) {
      _drawFreckles(canvas, w, h);
    }

    final nosePath = Path()
      ..moveTo(w * 0.5, h * 0.48)
      ..lineTo(w * 0.47, h * 0.56)
      ..quadraticBezierTo(w * 0.5, h * 0.585, w * 0.53, h * 0.56);
    canvas.drawPath(
      nosePath,
      Paint()
        ..color = palette.skinShade
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    final mouthCtrlY = h * (0.62 + 0.058 * smile);
    final mouthEndY = h * (0.645 - 0.012 * smile);
    final mouthPath = Path()
      ..moveTo(w * 0.42, mouthEndY)
      ..quadraticBezierTo(w * 0.5, mouthCtrlY, w * 0.58, mouthEndY);
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = palette.mouth
        ..strokeWidth = w * 0.026
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawHair(Canvas canvas, double w, double h, Color color) {
    // 사람 형태 (huckleberryFinn) 만 이 헬퍼 사용. 나머지 style 은 paint() 에서
    // 조기 return 되어 이 헬퍼로 진입 안 함.
    if (style != AiStyle.huckleberryFinn) return;
    final paint = Paint()..color = color;
    // Messy, slightly unkempt mop with a few tufts on top.
    final path = Path()
      ..moveTo(w * 0.23, h * 0.48)
      ..quadraticBezierTo(w * 0.16, h * 0.22, w * 0.28, h * 0.16)
      ..quadraticBezierTo(w * 0.32, h * 0.06, w * 0.40, h * 0.14)
      ..quadraticBezierTo(w * 0.45, h * 0.04, w * 0.52, h * 0.12)
      ..quadraticBezierTo(w * 0.60, h * 0.05, w * 0.66, h * 0.15)
      ..quadraticBezierTo(w * 0.74, h * 0.08, w * 0.78, h * 0.20)
      ..quadraticBezierTo(w * 0.84, h * 0.26, w * 0.77, h * 0.48)
      ..quadraticBezierTo(w * 0.73, h * 0.28, w * 0.5, h * 0.27)
      ..quadraticBezierTo(w * 0.27, h * 0.28, w * 0.23, h * 0.48)
      ..close();
    canvas.drawPath(path, paint);
    // A small forelock dangling onto the forehead.
    final forelock = Path()
      ..moveTo(w * 0.46, h * 0.26)
      ..quadraticBezierTo(w * 0.50, h * 0.36, w * 0.56, h * 0.30)
      ..quadraticBezierTo(w * 0.52, h * 0.27, w * 0.46, h * 0.26)
      ..close();
    canvas.drawPath(forelock, paint);
  }

  /// Blob — 인간 형태 아님. 크림색 둥근 몸체 + 홍조 볼 + 심플 눈/미소.
  void _paintBlob(Canvas canvas, double w, double h, _Palette palette) {
    // 큰 둥근 몸체 — canvas 중앙 정렬.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.5),
        width: w * 0.78,
        height: h * 0.78,
      ),
      Paint()..color = palette.skin,
    );
    // 홍조 볼.
    final cheek = Paint()..color = palette.mouth.withValues(alpha: 0.18);
    canvas.drawCircle(Offset(w * 0.30, h * 0.57), w * 0.062, cheek);
    canvas.drawCircle(Offset(w * 0.70, h * 0.57), w * 0.062, cheek);
    _drawSimpleFace(canvas, w, h, palette, eyeY: 0.47, mouthY: 0.65);
  }

  /// DewDrop — 이슬방울 실루엣 + 하이라이트 + 심플 눈/미소.
  void _paintDewDrop(Canvas canvas, double w, double h, _Palette palette) {
    // 뾰족한 위쪽 + 둥근 아래쪽 물방울.
    final drop = Path()
      ..moveTo(w * 0.5, h * 0.08)
      ..quadraticBezierTo(w * 0.84, h * 0.46, w * 0.80, h * 0.72)
      ..quadraticBezierTo(w * 0.66, h * 0.94, w * 0.5, h * 0.94)
      ..quadraticBezierTo(w * 0.34, h * 0.94, w * 0.20, h * 0.72)
      ..quadraticBezierTo(w * 0.16, h * 0.46, w * 0.5, h * 0.08)
      ..close();
    canvas.drawPath(drop, Paint()..color = palette.skin);
    // 하단 그림자.
    final shade = Path()
      ..moveTo(w * 0.5, h * 0.55)
      ..quadraticBezierTo(w * 0.75, h * 0.72, w * 0.72, h * 0.86)
      ..quadraticBezierTo(w * 0.62, h * 0.94, w * 0.5, h * 0.94)
      ..close();
    canvas.drawPath(
      shade,
      Paint()..color = palette.skinShade.withValues(alpha: 0.4),
    );
    // 하이라이트 (물방울 반사감).
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.36, h * 0.36),
        width: w * 0.13,
        height: h * 0.20,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );
    _drawSimpleFace(canvas, w, h, palette, eyeY: 0.58, mouthY: 0.75);
  }

  /// blob / dewDrop 이 공용으로 쓰는 심플 눈+미소.
  void _drawSimpleFace(
    Canvas canvas,
    double w,
    double h,
    _Palette palette, {
    required double eyeY,
    required double mouthY,
  }) {
    final eyeOpen = _eyeOpen;
    final smile = _smile;
    final pupilPaint = Paint()..color = const Color(0xFF2E2620);
    for (final ex in const [0.40, 0.60]) {
      final center = Offset(w * ex, h * eyeY);
      if (eyeOpen < 0.15) {
        canvas.drawLine(
          Offset(w * ex - w * 0.04, h * eyeY),
          Offset(w * ex + w * 0.04, h * eyeY),
          Paint()
            ..color = palette.mouth
            ..strokeWidth = w * 0.018
            ..strokeCap = StrokeCap.round,
        );
      } else {
        canvas.drawCircle(center, w * 0.03 * eyeOpen, pupilPaint);
      }
    }
    final mouthCtrlY = h * (mouthY + 0.03 + 0.03 * smile);
    final mouthEndY = h * (mouthY + 0.005);
    final mouthPath = Path()
      ..moveTo(w * 0.43, mouthEndY)
      ..quadraticBezierTo(w * 0.5, mouthCtrlY, w * 0.57, mouthEndY);
    canvas.drawPath(
      mouthPath,
      Paint()
        ..color = palette.mouth
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawFreckles(Canvas canvas, double w, double h) {
    final paint = Paint()..color = const Color(0xAA7A4A2A);
    final dots = <Offset>[
      Offset(w * 0.36, h * 0.55),
      Offset(w * 0.40, h * 0.535),
      Offset(w * 0.44, h * 0.555),
      Offset(w * 0.56, h * 0.555),
      Offset(w * 0.60, h * 0.535),
      Offset(w * 0.64, h * 0.55),
      Offset(w * 0.48, h * 0.545),
      Offset(w * 0.52, h * 0.545),
    ];
    final r = w * 0.008;
    for (final d in dots) {
      canvas.drawCircle(d, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AiFacePainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.style != style ||
      oldDelegate.viewerCountryCode != viewerCountryCode;
}
