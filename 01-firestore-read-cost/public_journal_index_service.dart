// 발췌: lib/app/services/public_journal_index_service.dart
// (import 경로 등은 원본 레포 기준이라 그대로 컴파일되지 않습니다.)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../db/app_database.dart';
import '../db/daos/public_journal_indexes_dao.dart';
import 'firestore_paths.dart';
import 'last_viewed_public_entry_service.dart';

/// app_config/public_journal_indexes 의 `current` 배열을 drift 로 캐시하고
/// reactive stream 으로 노출. 캐시 TTL 1 시간 — 그 이후 호출이면 Firestore
/// 재 fetch 후 통째 교체.
abstract class PublicJournalIndexService {
  /// drift 캐시가 비어있거나 cachedAt 이 TTL 초과면 Firestore fetch + replaceAll.
  /// 그렇지 않으면 no-op.
  Future<void> ensureCached();

  /// drift 의 인덱스 row 들을 watch — contentLength desc 정렬.
  Stream<List<PublicJournalIndexRow>> watchIndex();
}

class FirebasePublicJournalIndexService implements PublicJournalIndexService {
  FirebasePublicJournalIndexService({
    required AppDatabase appDatabase,
    required LastViewedPublicEntryService lastViewedPublicEntryService,
    FirebaseFirestore? firestore,
  }) : _db = appDatabase,
       _lastViewed = lastViewedPublicEntryService,
       _firestore = firestore ?? FirebaseFirestore.instance;

  static const _arrayField = 'current';
  static const _cacheTtl = Duration(hours: 1);

  String get _indexDocId => FirestorePaths.publicJournalIndexesDocId;

  final AppDatabase _db;
  final LastViewedPublicEntryService _lastViewed;
  final FirebaseFirestore _firestore;

  PublicJournalIndexesDao get _dao => _db.publicJournalIndexesDao;

  @override
  Future<void> ensureCached() async {
    try {
      final cachedAt = await _dao.latestCachedAt();
      final now = DateTime.now();
      if (cachedAt != null && now.difference(cachedAt) < _cacheTtl) {
        return; // 캐시 신선 — no-op.
      }

      final snap = await FirestorePaths.appConfig(
        _firestore,
      ).doc(_indexDocId).get();
      if (!snap.exists) return;

      final data = snap.data() ?? <String, dynamic>{};
      final list = (data[_arrayField] as List<dynamic>?) ?? const [];

      // 새 인덱스 entry 들을 entryId → row 매핑으로 변환.
      final newRowsByEntryId = <String, PublicJournalIndexesCompanion>{};
      final newOrder = <String>[]; // 새 인덱스에 들어온 순서 보존.
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final entryId = raw['entryId'] as String?;
        final visibleUntil = raw['visibleUntil'];
        if (entryId == null || entryId.isEmpty) continue;
        if (visibleUntil is! Timestamp) continue;
        if (newRowsByEntryId.containsKey(entryId)) continue;
        final updatedAt = raw['updatedAt'];
        newRowsByEntryId[entryId] = PublicJournalIndexesCompanion(
          entryId: Value(entryId),
          contentLength: Value((raw['contentLength'] as num?)?.toInt() ?? 0),
          visibleUntil: Value(visibleUntil.toDate()),
          updatedAt: Value(updatedAt is Timestamp ? updatedAt.toDate() : null),
          cachedAt: Value(now),
        );
        newOrder.add(entryId);
      }

      // 병합 — lastViewedEntryId 가 있으면 사용자 reading position 유지.
      final lastViewedEntryId = await _lastViewed.load();
      final ordered = await _mergeOrdered(
        newRowsByEntryId: newRowsByEntryId,
        newOrder: newOrder,
        lastViewedEntryId: lastViewedEntryId,
      );

      // position 0.0..N-1.0 부여. real 컬럼이라 double 로 정수값 부여 —
      // 본인 작성 시 mid 삽입은 이 정수 사이 fractional (예: 2.5) 로 채움.
      final finalRows = <PublicJournalIndexesCompanion>[];
      for (var i = 0; i < ordered.length; i++) {
        final base = newRowsByEntryId[ordered[i]]!;
        finalRows.add(
          PublicJournalIndexesCompanion(
            entryId: base.entryId,
            contentLength: base.contentLength,
            visibleUntil: base.visibleUntil,
            updatedAt: base.updatedAt,
            cachedAt: base.cachedAt,
            position: Value(i.toDouble()),
          ),
        );
      }

      await _dao.replaceAll(finalRows);

      // lastViewedEntryId 가 병합 결과에서 사라졌으면, 안 본 첫 entry 로 갱신해
      // 다음 복원이 unread 첫 entry 로 떨어지게 함.
      if (lastViewedEntryId != null &&
          !newRowsByEntryId.containsKey(lastViewedEntryId)) {
        final survived = ordered.toSet();
        final fallback = newOrder.firstWhere(
          (id) => survived.contains(id),
          orElse: () => '',
        );
        if (fallback.isNotEmpty) {
          await _lastViewed.save(fallback);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('PublicJournalIndexService.ensureCached failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// readEntry (이전 인덱스에서 lastViewed 까지) + unreadEntry (새 인덱스 중
  /// readEntry 에 없는 것) 의 병합. read 가 새 인덱스에서 빠진 경우 drop.
  Future<List<String>> _mergeOrdered({
    required Map<String, PublicJournalIndexesCompanion> newRowsByEntryId,
    required List<String> newOrder,
    required String? lastViewedEntryId,
  }) async {
    if (lastViewedEntryId == null) {
      // 사용자 history 없음 → 새 인덱스 순서 그대로.
      return List.of(newOrder);
    }

    final oldRows = await _dao.all();
    final oldOrder = oldRows.map((r) => r.entryId).toList(growable: false);
    final lastIdx = oldOrder.indexOf(lastViewedEntryId);
    if (lastIdx < 0) {
      // 이전 인덱스에 lastViewedEntryId 가 없음 (희귀 — pref 만 살아있고 drift
      // 가 비었거나 mismatch). 그냥 새 인덱스 순서 사용.
      return List.of(newOrder);
    }

    final readEntry = oldOrder.sublist(0, lastIdx + 1);
    // updateReadEntry = readEntry ∩ newIndex (순서는 readEntry 그대로).
    final updateReadEntry = readEntry
        .where((id) => newRowsByEntryId.containsKey(id))
        .toList(growable: false);
    final readSet = updateReadEntry.toSet();
    final unreadEntry = newOrder
        .where((id) => !readSet.contains(id))
        .toList(growable: false);
    return [...updateReadEntry, ...unreadEntry];
  }

  @override
  Stream<List<PublicJournalIndexRow>> watchIndex() => _dao.watchAll();
}
