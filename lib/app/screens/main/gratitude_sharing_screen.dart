// 부분 발췌본입니다. 원본 lib/app/screens/main/gratitude_sharing_screen.dart
// 는 감사 나눔 피드 화면 전체(리액션, 신고, presence 표시, 무한 스크롤 등)
// 를 담고 있으며, 이 쇼케이스와 무관한 부분은 뺐습니다. import 경로도 원본
// 레포 기준이라 이 파일만으로는 컴파일되지 않습니다.
//
// 여기 남긴 것: 카드 스와이프 시 이웃 카드들에 블러 · 스케일 · 오버랩을
// 주는 전환 효과. PageController 의 현재 page(double, 소수점 포함)를
// AnimatedBuilder 로 매 프레임 읽어서, 화면 중앙과의 거리로 각 카드의
// scale/opacity/blur/offset 을 계산한다.

late PageController _pageController;

void _initController() {
  _pageController = PageController(viewportFraction: 0.89);
}

Widget _buildCard(BuildContext context, int index, Widget child) {
  return AnimatedBuilder(
    animation: _pageController,
    builder: (context, _) {
      double page = _currentPageIndex.toDouble();
      if (_pageController.hasClients) {
        final currentPage = _pageController.page;
        if (currentPage != null) {
          page = currentPage;
        }
      }

      // 화면 중앙(현재 page)에서 이 카드(index)까지의 거리 — 0(중앙)~1(이웃).
      final distance = (page - index).abs().clamp(0.0, 1.0);
      final scale = 1 - (distance * 0.14);
      final opacity = 1 - (distance * 0.5);
      final blurSigma = distance * 2.6;
      final direction = index > page ? -1.0 : 1.0;
      final overlapOffset = direction * (distance * 26.w);

      return Transform.translate(
        offset: Offset(overlapOffset, 0),
        child: Transform.scale(
          scale: scale.clamp(0.9, 1.0),
          alignment: Alignment.center,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
    child: child,
  );
}
