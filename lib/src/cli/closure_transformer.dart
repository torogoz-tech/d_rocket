/// .g — file-level closure → Expr transformer:
///
/// Walks a Dart source file and rewrites every
/// closure LINQ call (`q.where_((t) => …)`,
/// `q.orderBy_((t) => …)`, etc.) to the equivalent
/// `Expr.lambda(...)` form, so the user can write
/// closures and get the SQL translation without
/// going through the per-line CLI.
///
/// MVP scope (single-line closures only):
/// - `where_((t) => body)` → `where_(Expr.lambda(...))`
/// - `orderBy_((t) => body)` → `orderBy_(Expr.lambda(...))`
/// - `orderByDescending_`, `thenBy_`, `thenByDescending_`
/// — same treatment
///
/// Not supported in the MVP:
/// - Multi-line closures (`(t) => { ... }`)
/// - Closures with nested `=>` (rare in practice)
/// - Closures that span multiple statements
///
/// For multi-line cases, the user can either inline
/// the closure to a single line, or run the CLI on
/// each line manually (`closure '(t) => …'`).
library;

import '../linq/closure_translator.dart';

/// .g: the closure LINQ methods that
/// accept either an `Expr` or a closure. Each entry
/// is a regex pattern used to find candidate call
/// sites in a Dart file.
const List<Pattern> closureLinqMethods = <Pattern>[
  r'\.where_\s*\(',
  r'\.orderBy_\s*\(',
  r'\.orderByDescending_\s*\(',
  r'\.thenBy_\s*\(',
  r'\.thenByDescending_\s*\(',
];

/// .g: walk [source] and rewrite every
/// closure LINQ call site to its `Expr.lambda(...)`
/// equivalent. Returns the transformed source.
///
/// The rewrite is conservative: only single-line
/// closures (`(t) => body`) on a single line are
/// transformed. Multi-line lambdas are skipped.
///
/// The accompanying [TransformReport] list is filled
/// with one entry per closure LINQ call site found,
/// describing whether it was rewritten or skipped.
String transformFileSource(
  String source, {
  List<TransformReport>? reportSink,
}) {
  final StringBuffer out = StringBuffer();
  final List<String> lines = source.split('\n');
  int lineIndex = 0;
  for (int i = 0; i < lines.length; i++) {
    lineIndex++;
    final String line = lines[i];
    String transformed = line;
    for (final Pattern pat in closureLinqMethods) {
      final RegExp re = RegExp(pat as String);
      for (final RegExpMatch m in re.allMatches(line)) {
        final int openParen = m.end - 1; // position of the `(`
        final ParenSpan? span = findMatchingParen(line, openParen);
        if (span == null) continue;
        final String inside = line.substring(span.start + 1, span.end);
        final LambdaMatch? lm = tryParseSingleLineLambda(inside);
        if (lm == null) {
          reportSink?.add(TransformReport(
            line: lineIndex,
            method: line.substring(m.start, m.start + m[0]!.length).trim(),
            status: 'skipped (multi-line or non-lambda)',
          ));
          continue;
        }
        final String expr = translateClosureBody(
          body: lm.body,
          paramName: lm.param,
        );
        final int absStart = m.start + m[0]!.length - 1; // the `(`
        final int absEnd = span.end + 1; // the matching `)`
        final String before = transformed.substring(0, absStart);
        final String after = transformed.substring(absEnd);
        final String newArg =
            "(Expr.lambda(<Expr>[ParamExpr('${lm.param}')], $expr))";
        transformed = before + newArg + after;
        reportSink?.add(TransformReport(
          line: lineIndex,
          method: line.substring(m.start, m.start + m[0]!.length).trim(),
          status: 'rewrote: ${lm.param} => ${lm.body}',
        ));
        // Only the FIRST closure per line — the
        // outer loop would re-match inside the
        // generated Expr code otherwise.
        break;
      }
    }
    out.write(transformed);
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// .g: one entry per closure LINQ call
/// site found by [transformFileSource].
class TransformReport {
  TransformReport({
    required this.line,
    required this.method,
    required this.status,
  });
  final int line;
  final String method;
  final String status;
}

/// .g: find the index of the `)` that
/// matches the `(` at [openIndex] in [s]. Returns
/// null if unbalanced.
ParenSpan? findMatchingParen(String s, int openIndex) {
  if (openIndex >= s.length || s[openIndex] != '(') return null;
  int depth = 0;
  bool inString = false;
  String? quote;
  for (int i = openIndex; i < s.length; i++) {
    final String c = s[i];
    if (inString) {
      if (c == quote) inString = false;
      continue;
    }
    if (c == "'" || c == '"') {
      inString = true;
      quote = c;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return ParenSpan(openIndex, i);
    }
  }
  return null;
}

/// .g: a matched pair of parens.
class ParenSpan {
  const ParenSpan(this.start, this.end);
  final int start;
  final int end;
}

/// .g: try to parse a single-line lambda
/// `(name) => body` from [s]. Returns null if [s]
/// is not a single-line closure.
LambdaMatch? tryParseSingleLineLambda(String s) {
  final String trimmed = s.trim();
  final RegExp lambdaRe =
      RegExp(r"""^\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)\s*=>\s*([^=].*)$""");
  final RegExpMatch? m = lambdaRe.firstMatch(trimmed);
  if (m == null) return null;
  final String body = m.group(2)!.trim();
  if (body.contains('\n')) return null;
  return LambdaMatch(param: m.group(1)!, body: body);
}

/// .g: a parsed single-line closure.
class LambdaMatch {
  const LambdaMatch({required this.param, required this.body});
  final String param;
  final String body;
}
