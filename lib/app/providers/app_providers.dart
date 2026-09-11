// 부분 발췌본입니다. 원본 lib/app/providers/app_providers.dart 는 앱의
// 모든 Riverpod provider(서비스 DI, 화면별 상태 등) 590줄 이상을 담고
// 있으며, 이 쇼케이스와 무관한 provider 는 뺐습니다. import 경로도 원본
// 레포 기준이라 이 파일만으로는 컴파일되지 않습니다.
//
// 여기 남긴 것: provider 계층 구성 패턴 — 서비스 DI, 인증 상태에 의존하는
// 스트림, 캐시 우선 프로필 조합, family.autoDispose 로 화면별 구독 생명
// 주기를 관리하는 방식.

// ---------------------------------------------------------------------
// 1. 서비스 DI — 단순 Provider 로 싱글턴처럼 구성
// ---------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return FirebaseAuthService();
});

final journalServiceProvider = Provider<JournalService>((ref) {
  return FirebaseJournalService(
    appDatabase: ref.watch(appDatabaseProvider),
    authService: ref.watch(authServiceProvider),
  );
});

// ---------------------------------------------------------------------
// 2. 인증 상태 → 프로필로 이어지는 provider 체인
// ---------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// app_config/runtime mirror — 인증 후 부팅 시 1회 subscribe, 평생 watch.
/// 인증 안 된 상태에선 null stream (rule 이 isSignedIn() 임).
final appRuntimeConfigProvider = StreamProvider<AppRuntimeConfig?>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) return Stream<AppRuntimeConfig?>.value(null);
  return FirestorePaths.appConfig(FirebaseFirestore.instance)
      .doc('runtime')
      .snapshots()
      .map((doc) => doc.exists ? AppRuntimeConfig.fromDocument(doc) : null);
});

/// 본인 공개 프로필 — cache-first (SharedPreferences). 캐시 hit 시 Firestore
/// read 0. mutation (updateCurrentUserProfile) 시 캐시 같이 갱신되므로 별도
/// invalidate 불필요. 로그아웃 시 auth 가 prefs 키 클리어.
final currentUserPublicProfileProvider = FutureProvider<UserPublicProfile?>((
  ref,
) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.asData?.value;
  if (user == null) return null;
  return ref.watch(userProfileServiceProvider).getSelfPublicProfile();
});

/// public 은 cache-first, private 은 stream — 변경 시 재결합.
final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.asData?.value;
  if (user == null) {
    return Stream<UserProfile?>.value(null);
  }
  final publicAsync = ref.watch(currentUserPublicProfileProvider);
  final publicValue = publicAsync.asData?.value;
  if (publicValue == null) {
    // 로딩 중이거나 doc 없음.
    return publicAsync.isLoading
        ? const Stream<UserProfile?>.empty()
        : Stream<UserProfile?>.value(null);
  }
  return ref
      .watch(userProfileServiceProvider)
      .watchSelfPrivateProfile()
      .map(
        (private) => UserProfile(
          publicProfile: publicValue,
          privateProfile:
              private ?? UserPrivateProfile.fromDocument(null, uid: user.uid),
        ),
      );
});

// ---------------------------------------------------------------------
// 3. family.autoDispose — 화면(entryId)별로 구독을 열고, 화면이 닫히면
//    자동으로 해제되는 provider. 댓글 목록처럼 "지금 보는 entry 한정"
//    데이터에 사용.
// ---------------------------------------------------------------------

final journalCommentsProvider = StreamProvider.family
    .autoDispose<List<JournalComment>, String>((ref, entryId) {
      return ref
          .watch(journalCommentServiceProvider)
          .watchComments(entryId: entryId);
    });
