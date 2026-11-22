import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('DeltaSync emits only changed fields and deletes', () {
    final List<SyncChange> changes = DeltaSync.diff(
      tableName: 'accounts',
      primaryKey: 'id',
      previous: <String, Object?>{
        'id': '1',
        'balance': 10,
        'status': 'open',
      },
      current: <String, Object?>{
        'id': '1',
        'balance': 15,
        'status': 'open',
      },
      version: 2,
    );
    expect(changes, hasLength(1));
    expect(changes.single.payload, <String, Object?>{'balance': 15});

    final List<SyncChange> deleted = DeltaSync.diff(
      tableName: 'accounts',
      primaryKey: 'id',
      previous: <String, Object?>{'id': '1'},
      current: null,
      version: 3,
    );
    expect(deleted.single.type, SyncChangeType.delete);
    expect(deleted.single.payload, isNull);
  });
}
