import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/ai_journal_dates_dao.dart';
import 'daos/journal_entries_dao.dart';
import 'daos/profiles_dao.dart';
import 'daos/public_journal_indexes_dao.dart';

part 'app_database.g.dart';

/// users 컬렉션 mirror. 본인/AI/타인 모두 한 테이블에 보관.
/// 구분은 `isAi` + uid 비교로 처리. AI 만 `journalWrittenCount` 의미 있음.
@DataClassName('ProfileRow')
@TableIndex(name: 'idx_profiles_is_ai', columns: {#isAi})
class Profiles extends Table {
  TextColumn get uid => text()();
  TextColumn get nickname => text().withDefault(const Constant(''))();
  TextColumn get countryCode => text().withDefault(const Constant(''))();
  TextColumn get photoPath => text().nullable()();
  TextColumn get bio => text().nullable()();
  // 언어별 자기소개 (AI 계정 위주, 일반 계정은 보통 null).
  TextColumn get bioUs => text().nullable()();
  TextColumn get bioJp => text().nullable()();
  TextColumn get bioKr => text().nullable()();
  BoolColumn get isAi => boolean().withDefault(const Constant(false))();
  TextColumn get aiStyle => text().nullable()();
  IntColumn get journalWrittenCount =>
      integer().withDefault(const Constant(0))();

  /// AI 전용 — 마지막 일기 작성 시각.
  DateTimeColumn get lastJournalWrittenAt => dateTime().nullable()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  // 로컬에 캐시한 시점 — TTL/정리 정책 용도.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {uid};
}

/// public_journal_entries 컬렉션 mirror. 본인/AI/타인 공개 일지 모두 한 테이블.
@DataClassName('JournalEntryRow')
@TableIndex(name: 'idx_journal_entries_auth_uid', columns: {#authUid})
@TableIndex(name: 'idx_journal_entries_written_at', columns: {#writtenAt})
@TableIndex(name: 'idx_journal_entries_visible_until', columns: {#visibleUntil})
class JournalEntries extends Table {
  TextColumn get id => text()();
  TextColumn get authUid => text()();
  TextColumn get authorNickname => text().withDefault(const Constant(''))();
  TextColumn get authorProfilePath => text().nullable()();
  TextColumn get authorCountryCode => text().withDefault(const Constant(''))();
  TextColumn get content => text().withDefault(const Constant(''))();
  // contentStyleRanges 는 JSON 문자열로 저장.
  TextColumn get contentStyleRangesJson => text().nullable()();
  IntColumn get contentLength => integer().withDefault(const Constant(0))();
  DateTimeColumn get writtenAt => dateTime()();
  DateTimeColumn get visibleUntil => dateTime().nullable()();
  IntColumn get commentCount => integer().withDefault(const Constant(0))();
  RealColumn get score => real().withDefault(const Constant(0))();
  BoolColumn get isReported => boolean().withDefault(const Constant(false))();
  BoolColumn get isAi => boolean().withDefault(const Constant(false))();
  TextColumn get authorAiStyle => text().nullable()();
  BoolColumn get shouldArchive =>
      boolean().withDefault(const Constant(false))();
  // 수정 이전 본문. 최초 작성 시 null, 1회 수정 시 이전 content 스냅샷.
  TextColumn get previousContent => text().nullable()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  // reactionTypeCounts 는 JSON 문자열. {"like": 3, ...} 형태.
  TextColumn get reactionTypeCountsJson => text().nullable()();
  // 내가 이 entry 에 한 reaction 타입들. JSON list 문자열. null = 아직 Firestore
  // 1회 fetch 안 함 (모름). '[]' = fetch 했고 반응 없음. '["mind"]' = 반응 있음.
  TextColumn get myReactionTypesJson => text().nullable()();
  // 로컬에 캐시한 시점 — TTL/정리 정책 용도.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI 의 users/{aiUid}/journal_dates 하위 컬렉션 mirror. 서버는 연 단위 doc
/// (months > MM > DD) 구조지만 로컬에선 일 단위 flat row 로 정규화 — 월별
/// 쿼리/캘린더 렌더링이 단순. (aiUid, year, month, day) 가 PK.
@DataClassName('AiJournalDateRow')
@TableIndex(name: 'idx_ai_journal_dates_ai_uid', columns: {#aiUid})
class AiJournalDates extends Table {
  TextColumn get aiUid => text()();
  IntColumn get year => integer()();
  IntColumn get month => integer()();
  IntColumn get day => integer()();
  // 서버의 days[MM][DD].updatedAt 미러 — entry 의 updatedAt 과 동일.
  DateTimeColumn get entryUpdatedAt => dateTime()();
  // 로컬에 캐시한 시점.
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {aiUid, year, month, day};
}

/// app_config/public_journal_indexes 의 `current` 배열 mirror — 공개 일기
/// 목록 탐색용. 항목 1 개 = 한 entry. PK 는 entryId.
@DataClassName('PublicJournalIndexRow')
class PublicJournalIndexes extends Table {
  TextColumn get entryId => text()();
  IntColumn get contentLength => integer().withDefault(const Constant(0))();
  DateTimeColumn get visibleUntil => dateTime().nullable()();
  // 서버측에서 entry 가 수정된 시점 (인덱스에 있는 entry 만 채워짐) — 클라 캐시
  // staleness 판단용. null = 아직 수정된 적 없음.
  DateTimeColumn get updatedAt => dateTime().nullable()();
  // 로컬에 캐시한 시점.
  DateTimeColumn get cachedAt => dateTime()();
  // 사용자가 본 history (앞) + 안 본 새 entries (뒤) 순서를 유지하기 위한
  // 명시적 정렬 키. replaceAll 시 0.0..N-1.0 부여. 본인 작성으로 중간 삽입
  // 시엔 앞/뒤 값의 중간 (예: 2.5) 로 넣어 shift 없이 O(1) 삽입 가능.
  RealColumn get position => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DriftDatabase(
  tables: [Profiles, JournalEntries, AiJournalDates, PublicJournalIndexes],
  daos: [
    ProfilesDao,
    JournalEntriesDao,
    AiJournalDatesDao,
    PublicJournalIndexesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 스키마 변경 시 +1 하고 `onUpgrade` 에 마이그레이션 step 추가.
  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        // journal_entries 에 본인 reactionType JSON 캐시 컬럼 추가.
        await m.addColumn(journalEntries, journalEntries.myReactionTypesJson);
      }
      if (from < 3) {
        // profiles.aiFaceStyle → aiStyle 컬럼 rename.
        await m.renameColumn(profiles, 'ai_face_style', profiles.aiStyle);
      }
      if (from < 4) {
        // AI 일기 작성일 캐시 테이블 추가.
        await m.createTable(aiJournalDates);
      }
      if (from < 5) {
        // journal_entries.author_profile_version 컬럼 제거.
        await m.alterTable(TableMigration(journalEntries));
      }
      if (from < 6) {
        // profiles 에 lastJournalWrittenAt 컬럼 추가 (calendar 의존 제거).
        await m.addColumn(profiles, profiles.lastJournalWrittenAt);
      }
      if (from < 7) {
        // 공개 일기 인덱스 미러 테이블 추가.
        await m.createTable(publicJournalIndexes);
      }
      if (from < 9) {
        // public_journal_indexes.writtenAt → visibleUntil 컬럼 rename.
        await m.renameColumn(
          publicJournalIndexes,
          'written_at',
          publicJournalIndexes.visibleUntil,
        );
      }
      if (from < 10) {
        // journal_entries.cache_deleted_at 컬럼 제거 (tombstone 정책 폐기).
        await m.alterTable(TableMigration(journalEntries));
      }
      if (from < 11) {
        // public_journal_indexes.updatedAt 추가 — 서버 stamp mirror,
        // entry cache staleness 판단용.
        await m.addColumn(publicJournalIndexes, publicJournalIndexes.updatedAt);
      }
      if (from < 12) {
        // public_journal_indexes.position 추가 — read/unread 병합 순서
        // 보존용 명시적 정렬 키.
        await m.addColumn(publicJournalIndexes, publicJournalIndexes.position);
      }
      if (from < 13) {
        // profiles 에 언어별 자기소개 컬럼 추가 (bio_US / bio_JP / bio_KR).
        await m.addColumn(profiles, profiles.bioUs);
        await m.addColumn(profiles, profiles.bioJp);
        await m.addColumn(profiles, profiles.bioKr);
      }
      if (from < 14) {
        // journal_entries.author_ai_face_style → author_ai_style 컬럼 rename.
        await m.renameColumn(
          journalEntries,
          'author_ai_face_style',
          journalEntries.authorAiStyle,
        );
      }
      if (from < 15) {
        // public_journal_indexes.position IntColumn → RealColumn. 기존
        // integer 값은 double 로 자동 캐스팅됨. 재생성.
        await m.alterTable(TableMigration(publicJournalIndexes));
      }
      if (from < 16) {
        // journal_entries 에 수정 이력용 previousContent 컬럼 추가.
        await m.addColumn(journalEntries, journalEntries.previousContent);
      }
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'grateful_day.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
