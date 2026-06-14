/// .c — closure → Expr translator:
///
/// Hand-rolled recursive-descent parser that takes the
/// body of a Dart closure lambda (the right side of
/// `(t) => …`) and emits the Dart source code that
/// constructs the corresponding `Expr` tree. The
/// emitted code is what the user would otherwise
/// have to write by hand:
///
/// ```dart
/// // User writes (closure form, .b):
/// q.where_((t) => t.status == 0 && t.priority > 5)
///
/// // Translator emits (Expr form, the SQL path):
/// q.where_(Expr.lambda(
/// `<Expr>`[ParamExpr('t')],
/// Expr.binary('&&',
/// Expr.binary('==',
/// Expr.member(ParamExpr('t'), 'status'),
/// Expr.const_(0)),
/// Expr.binary('>',
/// Expr.member(ParamExpr('t'), 'priority'),
/// Expr.const_(5)))))
/// ```
///
/// Supported (MVP):
/// - Identifiers (mapped to `ParamExpr(name)` if
/// they match the lambda parameter, else
/// `Expr.const_`)
///
/// - Numeric, string, boolean, null literals
/// (`Expr.const_(...)`)
///
/// - Member access: `a.b.c` → `Expr.member(...)`
///
/// - Method calls: `a.foo(b, c)` → `Expr.methodCall(...)`
///
/// - Binary ops: `==, !=, <, >, <=, >=, +, -, *, /,
/// %, &&, ||` → `Expr.binary(...)` with the right
/// precedence (low → high: `||`, `&&`, comparisons,
/// additive, multiplicative)
///
/// - Unary `!` → `Expr.unary('!', ...)`
///
/// Not supported (.d+):
/// - String interpolation (`'$name is $age'`)
/// - List/map literals
/// - Ternary (`a ? b: c`)
/// - Null-aware (`?.`, `??`)
///
/// For unsupported cases, the translator throws
/// [UnsupportedError] with a clear message — the
/// user can fall back to manual `Expr.lambda(...)`.
library;

/// .c: top-level entry. Translates
/// [body] (a closure expression, no arrow, no params)
/// into Dart source that constructs the `Expr` tree.
/// [paramName] is the lambda parameter name (used to
/// decide which identifiers become `ParamExpr`).
String translateClosureBody({
  required String body,
  required String paramName,
}) {
  final _Parser p = _Parser(body, paramName: paramName);
  final String expr = p.parseExpr();
  // Ensure we consumed the whole body.
  p.expectEnd();
  return expr;
}

// ─── Lexer ────────────────────────────────────────────────────

enum _TokKind {
  identifier,
  intLiteral,
  stringLiteral,
  boolLiteral,
  nullLiteral,
  lParen,
  rParen,
  lBracket,
  rBracket,
  lBrace,
  rBrace,
  comma,
  colon,
  dot,
  bang,
  plus,
  minus,
  star,
  slash,
  percent,
  eqEq,
  notEq,
  lt,
  gt,
  ltEq,
  gtEq,
  ampAmp,
  barBar,
  question, // ?
  questionQuestion, // ??
  questionDot, // ?.
  eof,
}

class _Token {
  const _Token(this.kind, this.text, {this.stringContent = ''});
  final _TokKind kind;
  final String text;

  /// .d: for [_TokKind.stringLiteral],
  /// the un-quoted content (e.g. for `"hello $name"`
  /// the content is `hello $name`). Empty for other
  /// token kinds. Used by the parser to walk string
  /// interpolation.
  final String stringContent;
}

class _Lexer {
  _Lexer(this.src) : _chars = src.split('');
  final String src;
  final List<String> _chars;
  int _i = 0;

  _Token next() {
    _skipWs();
    if (_i >= _chars.length) return const _Token(_TokKind.eof, '');
    final String c = _chars[_i];
    // Punctuation.
    if (c == '(') {
      _i++;
      return const _Token(_TokKind.lParen, '(');
    }
    if (c == ')') {
      _i++;
      return const _Token(_TokKind.rParen, ')');
    }
    if (c == '[') {
      _i++;
      return const _Token(_TokKind.lBracket, '[');
    }
    if (c == ']') {
      _i++;
      return const _Token(_TokKind.rBracket, ']');
    }
    if (c == ',') {
      _i++;
      return const _Token(_TokKind.comma, ',');
    }
    if (c == '.') {
      // Could be `.` (member) or start of a float like `.5`.
      if (_i + 1 < _chars.length && _isDigit(_chars[_i + 1])) {
        return _readNumber();
      }
      _i++;
      return const _Token(_TokKind.dot, '.');
    }
    if (c == '!') {
      if (_peek('=')) {
        _i += 2;
        return const _Token(_TokKind.notEq, '!=');
      }
      _i++;
      return const _Token(_TokKind.bang, '!');
    }
    if (c == '+') {
      _i++;
      return const _Token(_TokKind.plus, '+');
    }
    if (c == '-') {
      _i++;
      return const _Token(_TokKind.minus, '-');
    }
    if (c == '*') {
      _i++;
      return const _Token(_TokKind.star, '*');
    }
    if (c == '/') {
      _i++;
      return const _Token(_TokKind.slash, '/');
    }
    if (c == '%') {
      _i++;
      return const _Token(_TokKind.percent, '%');
    }
    if (c == '=' && _peek('=')) {
      _i += 2;
      return const _Token(_TokKind.eqEq, '==');
    }
    if (c == '<' && _peek('=')) {
      _i += 2;
      return const _Token(_TokKind.ltEq, '<=');
    }
    if (c == '>' && _peek('=')) {
      _i += 2;
      return const _Token(_TokKind.gtEq, '>=');
    }
    if (c == '<') {
      _i++;
      return const _Token(_TokKind.lt, '<');
    }
    if (c == '>') {
      _i++;
      return const _Token(_TokKind.gt, '>');
    }
    if (c == '&' && _peek('&')) {
      _i += 2;
      return const _Token(_TokKind.ampAmp, '&&');
    }
    if (c == '|' && _peek('|')) {
      _i += 2;
      return const _Token(_TokKind.barBar, '||');
    }
    if (c == '?') {
      if (_peek('?')) {
        _i += 2;
        return const _Token(_TokKind.questionQuestion, '??');
      }
      if (_peek('.')) {
        _i += 2;
        return const _Token(_TokKind.questionDot, '?.');
      }
      _i++;
      return const _Token(_TokKind.question, '?');
    }
    if (c == ':') {
      _i++;
      return const _Token(_TokKind.colon, ':');
    }
    if (c == '{') {
      _i++;
      return const _Token(_TokKind.lBrace, '{');
    }
    if (c == '}') {
      _i++;
      return const _Token(_TokKind.rBrace, '}');
    }
    // String literal.
    if (c == "'" || c == '"') {
      return _readString(c);
    }
    // Number.
    if (_isDigit(c) ||
        (c == '-' && _i + 1 < _chars.length && _isDigit(_chars[_i + 1]))) {
      return _readNumber();
    }
    // Identifier or keyword.
    if (_isIdentStart(c)) {
      return _readIdent();
    }
    throw FormatException(
      'closure_translator: unexpected character '
      "'$c' at offset $_i in body: $src",
    );
  }

  bool _peek(String s) {
    // .c fix: peek checks the char AFTER
    // the current one (lookahead of 1). The previous
    // implementation checked from `_i` itself, which
    // only ever returned true if the CURRENT char
    // matched — wrong for `>=`, `==`, `!=`, etc.
    if (_i + 1 + s.length > _chars.length) return false;
    for (int k = 0; k < s.length; k++) {
      if (_chars[_i + 1 + k] != s[k]) return false;
    }
    return true;
  }

  void _skipWs() {
    while (_i < _chars.length && _chars[_i].trim().isEmpty) {
      _i++;
    }
  }

  _Token _readIdent() {
    final int start = _i;
    while (_i < _chars.length && _isIdentPart(_chars[_i])) {
      _i++;
    }
    final String word = src.substring(start, _i);
    if (word == 'true' || word == 'false') {
      return _Token(_TokKind.boolLiteral, word);
    }
    if (word == 'null') {
      return const _Token(_TokKind.nullLiteral, 'null');
    }
    return _Token(_TokKind.identifier, word);
  }

  _Token _readNumber() {
    final int start = _i;
    if (_chars[_i] == '-') _i++;
    while (_i < _chars.length && _isDigit(_chars[_i])) {
      _i++;
    }
    if (_i < _chars.length && _chars[_i] == '.') {
      _i++;
      while (_i < _chars.length && _isDigit(_chars[_i])) {
        _i++;
      }
    }
    return _Token(_TokKind.intLiteral, src.substring(start, _i));
  }

  _Token _readString(String quote) {
    final int start = _i;
    _i++; // opening quote
    final int contentStart = _i;
    while (_i < _chars.length && _chars[_i] != quote) {
      if (_chars[_i] == r'\' && _i + 1 < _chars.length) {
        _i += 2;
      } else {
        _i++;
      }
    }
    if (_i >= _chars.length) {
      throw const FormatException('closure_translator: unterminated string');
    }
    final String content = src.substring(contentStart, _i);
    _i++; // closing quote
    return _Token(_TokKind.stringLiteral, src.substring(start, _i),
        stringContent: content);
  }

  static bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final int code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isIdentStart(String c) {
    if (c.isEmpty) return false;
    final int code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F || // _
        code == 0x24; // $
  }

  static bool _isIdentPart(String c) => _isDigit(c) || _isIdentStart(c);
}

// ─── Parser + code emitter ────────────────────────────────────

class _Parser {
  _Parser(this.src, {required this.paramName}) {
    _lexer = _Lexer(src);
    _cur = _lexer.next();
  }
  final String src;
  final String paramName;
  late final _Lexer _lexer;
  late _Token _cur;

  void _advance() => _cur = _lexer.next();

  String parseExpr() => _parseTernary();

  // Precedence (low → high):
  // a ? b: c (ternary)
  // a ?? b (null-coalesce)
  // ||
  // &&
  // ==, !=
  // <, >, <=, >=
  // +, -
  // *, /, %
  // unary !, member access, calls
  String _parseTernary() {
    final String cond = _parseNullCoalesce();
    if (_cur.kind == _TokKind.question) {
      _advance();
      final String thenBranch = parseExpr();
      if (_cur.kind != _TokKind.colon) {
        throw const FormatException(
            'closure_translator: expected `:` in ternary expression');
      }
      _advance();
      final String elseBranch = parseExpr();
      return "Expr.ternary("
          "cond: $cond, "
          "thenBranch: $thenBranch, "
          "elseBranch: $elseBranch)";
    }
    return cond;
  }

  String _parseNullCoalesce() {
    String left = _parseOr();
    while (_cur.kind == _TokKind.questionQuestion) {
      _advance();
      final String right = _parseOr();
      left = "Expr.coalesce($left, $right)";
    }
    return left;
  }

  String _parseOr() {
    String left = _parseAnd();
    while (_cur.kind == _TokKind.barBar) {
      _advance();
      final String right = _parseAnd();
      left = "Expr.binary('||', $left, $right)";
    }
    return left;
  }

  String _parseAnd() {
    String left = _parseEquality();
    while (_cur.kind == _TokKind.ampAmp) {
      _advance();
      final String right = _parseEquality();
      left = "Expr.binary('&&', $left, $right)";
    }
    return left;
  }

  String _parseEquality() {
    String left = _parseRelational();
    while (_cur.kind == _TokKind.eqEq || _cur.kind == _TokKind.notEq) {
      final String op = _cur.text;
      _advance();
      final String right = _parseRelational();
      left = "Expr.binary('$op', $left, $right)";
    }
    return left;
  }

  String _parseRelational() {
    String left = _parseAdditive();
    while (_cur.kind == _TokKind.lt ||
        _cur.kind == _TokKind.gt ||
        _cur.kind == _TokKind.ltEq ||
        _cur.kind == _TokKind.gtEq) {
      final String op = _cur.text;
      _advance();
      final String right = _parseAdditive();
      left = "Expr.binary('$op', $left, $right)";
    }
    return left;
  }

  String _parseAdditive() {
    String left = _parseMultiplicative();
    while (_cur.kind == _TokKind.plus || _cur.kind == _TokKind.minus) {
      final String op = _cur.text;
      _advance();
      final String right = _parseMultiplicative();
      left = "Expr.binary('$op', $left, $right)";
    }
    return left;
  }

  String _parseMultiplicative() {
    String left = _parseUnary();
    while (_cur.kind == _TokKind.star ||
        _cur.kind == _TokKind.slash ||
        _cur.kind == _TokKind.percent) {
      final String op = _cur.text;
      _advance();
      final String right = _parseUnary();
      left = "Expr.binary('$op', $left, $right)";
    }
    return left;
  }

  String _parseUnary() {
    if (_cur.kind == _TokKind.bang) {
      _advance();
      final String inner = _parseUnary();
      return "Expr.unary('!', $inner)";
    }
    return _parsePostfix();
  }

  String _parsePostfix() {
    String left = _parsePrimary();
    while (true) {
      if (_cur.kind == _TokKind.questionDot) {
        // .e: null-safe member access
        // `a?.b` → `Expr.nullSafe(a, 'b')`.
        _advance();
        if (_cur.kind != _TokKind.identifier) {
          throw const FormatException(
              'closure_translator: expected identifier after `?.`');
        }
        final String name = _cur.text;
        _advance();
        left = "Expr.nullSafe($left, '$name')";
      } else if (_cur.kind == _TokKind.dot) {
        // .c: lookahead — if the identifier
        // after the `.` is followed by `(`, treat it as
        // a method NAME (not a member). Consume the
        // args, then emit `Expr.call(receiver, name, args)`.
        // Otherwise it's a regular member access.
        _advance();
        if (_cur.kind != _TokKind.identifier) {
          throw const FormatException(
              'closure_translator: expected identifier after `.`');
        }
        final String name = _cur.text;
        _advance();
        if (_cur.kind == _TokKind.lParen) {
          // Method call.
          _advance();
          final List<String> args = <String>[];
          if (_cur.kind != _TokKind.rParen) {
            args.add(parseExpr());
            while (_cur.kind == _TokKind.comma) {
              _advance();
              args.add(parseExpr());
            }
          }
          if (_cur.kind != _TokKind.rParen) {
            throw const FormatException(
                'closure_translator: expected `)` to close method call');
          }
          _advance();
          final String argsList = args.map((String a) => a).join(', ');
          left = "Expr.call($left, '$name', <Expr>[$argsList])";
        } else {
          // Plain member access.
          left = "Expr.member($left, '$name')";
        }
      } else if (_cur.kind == _TokKind.lParen) {
        // Bare call like `foo` — treat as a
        // method call on the implicit receiver
        // (top-level function call). Emit
        // `Expr.call($left, 'call', <Expr>[...])`.
        // For the MVP, this is rarely useful (we
        // usually chain on a member), so it's a
        // minor edge case.
        _advance();
        final List<String> args = <String>[];
        if (_cur.kind != _TokKind.rParen) {
          args.add(parseExpr());
          while (_cur.kind == _TokKind.comma) {
            _advance();
            args.add(parseExpr());
          }
        }
        if (_cur.kind != _TokKind.rParen) {
          throw const FormatException(
              'closure_translator: expected `)` to close call');
        }
        _advance();
        final String argsList = args.map((String a) => a).join(', ');
        left = "Expr.call($left, 'call', <Expr>[$argsList])";
      } else {
        break;
      }
    }
    return left;
  }

  String _parsePrimary() {
    if (_cur.kind == _TokKind.lBrace) {
      // .e: map literal `{'a': 1, 'b': 2}`
      // → `Expr.map([MapEntry(...)])`. Empty map
      // `{}` → `Expr.map()`.
      _advance();
      final List<String> entries = <String>[];
      if (_cur.kind != _TokKind.rBrace) {
        // Parse key:value,key:value,...
        String parseEntry() {
          final String k = parseExpr();
          if (_cur.kind != _TokKind.colon) {
            throw const FormatException(
                'closure_translator: expected `:` in map literal');
          }
          _advance();
          final String v = parseExpr();
          return 'MapEntry($k, $v)';
        }

        entries.add(parseEntry());
        while (_cur.kind == _TokKind.comma) {
          _advance();
          if (_cur.kind == _TokKind.rBrace) break; // trailing comma
          entries.add(parseEntry());
        }
      }
      if (_cur.kind != _TokKind.rBrace) {
        throw const FormatException(
            'closure_translator: expected `}` to close map literal');
      }
      _advance();
      final String entriesList = entries.join(', ');
      return "Expr.map(<MapEntry<Expr, Expr>>[$entriesList])";
    }
    if (_cur.kind == _TokKind.lBracket) {
      // .d: list literal `[a, b, c]`
      // → `Expr.list([…])`. Empty list `` →
      // `Expr.list(<Expr>)`.
      _advance();
      final List<String> items = <String>[];
      if (_cur.kind != _TokKind.rBracket) {
        items.add(parseExpr());
        while (_cur.kind == _TokKind.comma) {
          _advance();
          items.add(parseExpr());
        }
      }
      if (_cur.kind != _TokKind.rBracket) {
        throw const FormatException(
            'closure_translator: expected `]` to close list literal');
      }
      _advance();
      final String itemsList = items.map((String i) => i).join(', ');
      return "Expr.list(<Expr>[$itemsList])";
    }
    if (_cur.kind == _TokKind.lParen) {
      _advance();
      final String inner = parseExpr();
      if (_cur.kind != _TokKind.rParen) {
        throw const FormatException(
            'closure_translator: expected `)` to close parenthesised expression');
      }
      _advance();
      return inner;
    }
    if (_cur.kind == _TokKind.identifier) {
      final String name = _cur.text;
      _advance();
      if (name == paramName) {
        return "ParamExpr('$paramName')";
      }
      // Otherwise treat as a constant identifier (e.g. an
      // imported enum value or top-level constant).
      return "Expr.const_($name)";
    }
    if (_cur.kind == _TokKind.intLiteral) {
      final String raw = _cur.text;
      _advance();
      if (raw.contains('.')) {
        return "Expr.const_($raw)";
      }
      return "Expr.const_($raw)";
    }
    if (_cur.kind == _TokKind.stringLiteral) {
      final String raw = _cur.text;
      final String content = _cur.stringContent;
      _advance();
      // .d: string interpolation. If the
      // content has no `$`, it's a plain literal.
      if (!content.contains(r'$')) {
        return "Expr.const_($raw)";
      }
      return _emitInterpolatedString(content);
    }
    if (_cur.kind == _TokKind.boolLiteral) {
      final String raw = _cur.text;
      _advance();
      return "Expr.const_($raw)";
    }
    if (_cur.kind == _TokKind.nullLiteral) {
      _advance();
      return 'Expr.const_(null)';
    }
    throw FormatException(
      'closure_translator: unexpected token in body: '
      '${_cur.text} (kind=${_cur.kind})\nBody: $src',
    );
  }

  void expectEnd() {
    if (_cur.kind != _TokKind.eof) {
      throw FormatException(
        'closure_translator: trailing token after expression: '
        "'${_cur.text}'. Full body: $src",
      );
    }
  }

  // ─── .d: string interpolation ──────────────────
  //
  // Walks [content] (the un-quoted body of a string
  // literal) and emits the Dart code that builds the
  // concatenated `Expr.binary('+', ...)` chain. Each
  // segment is either:
  //
  // * a literal part → `Expr.const_('…')`
  // * `$identifier` → `ParamExpr(...)` or
  // `Expr.const_(...)` depending on
  // whether the name matches the
  // lambda param
  // * `${expr}` → recurse into the parser for
  // the inner expression
  //
  // Caveat: `+` is numeric in SQL, so this chain
  // works in-memory (Dart's `+` on strings) but in
  // pure SQL the user would need a `CASE`-style
  // concat. For .d we keep `+` for simplicity.

  String _emitInterpolatedString(String content) {
    final List<String> parts = <String>[];
    final StringBuffer buf = StringBuffer();
    int i = 0;
    while (i < content.length) {
      final String c = content[i];
      if (c == r'\' && i + 1 < content.length) {
        // Escaped character (e.g. `\$`). Keep as-is in
        // the literal segment.
        buf.write(c);
        buf.write(content[i + 1]);
        i += 2;
        continue;
      }
      if (c == r'$') {
        if (i + 1 >= content.length) {
          // Trailing `$` — treat as literal.
          buf.write(c);
          i++;
          continue;
        }
        final String next = content[i + 1];
        if (next == '{') {
          // Brace interpolation: ${expr}.
          if (buf.isNotEmpty) {
            parts.add("Expr.const_('${_escapeString(buf.toString())}')");
            buf.clear();
          }
          // Find the matching `}` (simple, no nested
          // braces for MVP).
          int depth = 1;
          int j = i + 2;
          while (j < content.length && depth > 0) {
            if (content[j] == '{') {
              depth++;
            } else if (content[j] == '}') {
              depth--;
            }
            if (depth > 0) j++;
          }
          if (depth != 0) {
            throw FormatException(
              'closure_translator: unterminated `\${...}` '
              'in string interpolation: $content',
            );
          }
          final String inner = content.substring(i + 2, j);
          // Recurse: parse the inner expression with
          // a fresh parser, same paramName.
          final _Parser sub = _Parser(inner, paramName: paramName);
          final String innerExpr = sub.parseExpr();
          sub.expectEnd();
          parts.add(innerExpr);
          i = j + 1;
          continue;
        }
        if (_isIdentStart(next)) {
          // $identifier interpolation.
          if (buf.isNotEmpty) {
            parts.add("Expr.const_('${_escapeString(buf.toString())}')");
            buf.clear();
          }
          int j = i + 1;
          while (j < content.length && _isIdentPart(content[j])) {
            j++;
          }
          final String name = content.substring(i + 1, j);
          if (name == paramName) {
            parts.add("ParamExpr('$paramName')");
          } else {
            parts.add("Expr.const_($name)");
          }
          i = j;
          continue;
        }
        // `$` followed by a non-ident — treat as literal.
        buf.write(c);
        i++;
        continue;
      }
      buf.write(c);
      i++;
    }
    if (buf.isNotEmpty) {
      parts.add("Expr.const_('${_escapeString(buf.toString())}')");
    }
    if (parts.isEmpty) {
      return "Expr.const_('')";
    }
    String result = parts.first;
    for (int k = 1; k < parts.length; k++) {
      result = "Expr.binary('+', $result, ${parts[k]})";
    }
    return result;
  }

  static String _escapeString(String s) {
    return s
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$');
  }

  static bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final int code = c.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static bool _isIdentStart(String c) {
    if (c.isEmpty) return false;
    final int code = c.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F || // _
        code == 0x24; // $
  }

  static bool _isIdentPart(String c) => _isDigit(c) || _isIdentStart(c);
}
