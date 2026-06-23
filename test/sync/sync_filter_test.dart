// SYNC.3 — SyncFilter tests

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('AllowAllSyncFilter:', () {
    test('matches every change', () {
      const AllowAllSyncFilter f = AllowAllSyncFilter();
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'x': 1},
          version: 1,
        )),
        isTrue,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'users',
          pk: '2',
          type: SyncChangeType.delete,
          payload: null,
          version: 1,
        )),
        isTrue,
      );
    });
  });

  group('TableNameSyncFilter:', () {
    test('includes only the listed tables', () {
      const TableNameSyncFilter f = TableNameSyncFilter({'orders'});
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'x': 1},
          version: 1,
        )),
        isTrue,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'users',
          pk: '2',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'x': 1},
          version: 1,
        )),
        isFalse,
      );
    });
  });

  group('RecordSyncFilter:', () {
    test('skips changes for other tables', () {
      final RecordSyncFilter f = RecordSyncFilter(
        tableName: 'orders',
        predicate: (row) => row['userId'] == 42,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 42},
          version: 1,
        )),
        isFalse,
      );
    });

    test('skips changes whose row fails the predicate', () {
      final RecordSyncFilter f = RecordSyncFilter(
        tableName: 'orders',
        predicate: (row) => row['userId'] == 42,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 7},
          version: 1,
        )),
        isFalse,
      );
    });

    test('includes changes whose row matches', () {
      final RecordSyncFilter f = RecordSyncFilter(
        tableName: 'orders',
        predicate: (row) => row['userId'] == 42,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 42, 'total': 99},
          version: 1,
        )),
        isTrue,
      );
    });

    test('skips deletes (no payload)', () {
      final RecordSyncFilter f = RecordSyncFilter(
        tableName: 'orders',
        predicate: (row) => true,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.delete,
          payload: null,
          version: 1,
        )),
        isFalse,
      );
    });
  });

  group('ScopedSyncFilter:', () {
    test('AND combinator requires all to match', () {
      final ScopedSyncFilter f = ScopedSyncFilter.and([
        const TableNameSyncFilter({'orders'}),
        RecordSyncFilter(
          tableName: 'orders',
          predicate: (row) => row['userId'] == 42,
        ),
      ]);
      // Right table, right user → include.
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 42},
          version: 1,
        )),
        isTrue,
      );
      // Right table, wrong user → exclude.
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 7},
          version: 1,
        )),
        isFalse,
      );
      // Wrong table → exclude.
      expect(
        f.matches(SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'userId': 42},
          version: 1,
        )),
        isFalse,
      );
    });

    test('OR combinator requires any to match', () {
      final ScopedSyncFilter f = ScopedSyncFilter.or([
        const TableNameSyncFilter({'orders'}),
        const TableNameSyncFilter({'users'}),
      ]);
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{},
          version: 1,
        )),
        isTrue,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{},
          version: 1,
        )),
        isTrue,
      );
      expect(
        f.matches(SyncChange(
          tableName: 'products',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{},
          version: 1,
        )),
        isFalse,
      );
    });

    test('empty AND combinator returns true (vacuously)', () {
      final ScopedSyncFilter f = ScopedSyncFilter.and(<SyncFilter>[]);
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{},
          version: 1,
        )),
        isTrue,
      );
    });

    test('empty OR combinator returns false', () {
      final ScopedSyncFilter f = ScopedSyncFilter.or(<SyncFilter>[]);
      expect(
        f.matches(SyncChange(
          tableName: 'orders',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{},
          version: 1,
        )),
        isFalse,
      );
    });
  });
}
