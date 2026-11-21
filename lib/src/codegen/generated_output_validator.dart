/// Finds known invalid constructs in generated Dart source.
class GeneratedOutputValidator {
  const GeneratedOutputValidator._();

  /// Returns stable diagnostic labels for suspicious generated source.
  static List<String> findViolations(String source) {
    final List<String> violations = <String>[];
    if (source.contains('String??')) {
      violations.add('double-nullable type');
    }
    if (RegExp(r'null\s+as\s+DateTime').hasMatch(source)) {
      violations.add('nullable DateTime cast');
    }
    if (source.contains(r'$typeParamName') || source.contains(r'$jsonKey')) {
      violations.add('unexpanded template token');
    }
    if (source.contains('<dynamic>[]')) {
      violations.add('dynamic default list');
    }
    return violations;
  }
}
