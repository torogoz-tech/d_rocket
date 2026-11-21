import 'dart:io';

import 'package:d_rocket/src/codegen/generated_output_validator.dart';

void main() {
  final Directory root = Directory.current;
  final List<String> failures = <String>[];
  for (final FileSystemEntity entity in _generatedFiles(root)) {
    final File file = entity as File;
    final List<String> violations = GeneratedOutputValidator.findViolations(
      file.readAsStringSync(),
    );
    for (final String violation in violations) {
      failures.add('${file.path}: $violation');
    }
  }
  if (failures.isNotEmpty) {
    stderr.writeln('Generated output validation failed:');
    for (final String failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
  }
}

Iterable<FileSystemEntity> _generatedFiles(Directory root) sync* {
  for (final FileSystemEntity entity in root.listSync(recursive: true)) {
    final List<String> segments = entity.path.replaceAll('\\', '/').split('/');
    if (entity is File &&
        entity.path.endsWith('.g.dart') &&
        !segments.contains('.dart_tool') &&
        !segments.contains('.git') &&
        !segments.contains('build')) {
      yield entity;
    }
  }
}
