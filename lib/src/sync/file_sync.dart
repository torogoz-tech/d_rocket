/// 2.0.0 — file / blob sync (attachments).
///
/// Files (photos, PDFs, etc.) are out of
/// scope for the regular sync envelope
/// (which is JSON). The [FileSyncReference]
/// is a placeholder in a regular [SyncChange]
/// that points to a binary blob stored
/// elsewhere (the user's cloud storage).
///
/// In 2.0.0, we provide the abstraction. The
/// actual upload/download is the
/// responsibility of the user (usually via
/// `package:dio` or `package:http`).
///
/// Example:
///
/// ```dart
/// final ref = FileSyncReference(
///   tableName: 'attachments',
///   pk: '42',
///   field: 'photo',
///   remoteUrl: 'https://cdn.example.com/photo.jpg',
///   sizeBytes: 1024000,
///   contentType: 'image/jpeg',
/// );
/// ```
library;

/// A reference to a binary file/blob stored
/// in cloud storage. The [FileSyncProvider]
/// (not in 2.0.0 — stub) is responsible for
/// the actual upload/download.
class FileSyncReference {
  /// Creates a [FileSyncReference].
  const FileSyncReference({
    required this.tableName,
    required this.pk,
    required this.field,
    required this.remoteUrl,
    required this.sizeBytes,
    required this.contentType,
  });

  /// The local table name.
  final String tableName;

  /// The primary key of the row that owns
  /// this file.
  final String pk;

  /// The field name (e.g. `'photo'`,
  /// `'pdf'`).
  final String field;

  /// The remote URL where the file is stored.
  final String remoteUrl;

  /// The file size in bytes.
  final int sizeBytes;

  /// The MIME content type.
  final String contentType;

  @override
  String toString() =>
      'FileSyncReference($tableName/$pk/$field, '
      '$sizeBytes bytes, $contentType)';
}
