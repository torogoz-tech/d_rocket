/// .c — `d_rocket:closure` CLI:
///
/// Translates a closure lambda body into the
/// equivalent `Expr.lambda(...)` source code.
///
/// Usage:
///
/// ```bash
/// # Full lambda:
/// dart run d_rocket:closure '(t) => t.status == 0'
///
/// # Body + param (use —param / -p):
/// dart run d_rocket:closure -p t 't.status == 0'
/// ```
///
/// Output is the Dart code that, when pasted into
/// a `.where_(Expr.lambda(...))` call, reproduces the
/// lambda's behaviour as a SQL-translatable Expr tree.
library;

import 'dart:io';

import 'package:d_rocket/src/cli/closure_transformer.dart';
import 'package:d_rocket/src/linq/closure_translator.dart';

const String _kBanner = '''
┌─────────────────────────────────────────────┐
│ d_rocket closure → Expr translator          │
└─────────────────────────────────────────────┘''';

Future<int> main(List<String> args) async {
  if (args.isEmpty ||
      args.first == 'help' ||
      args.first == '--help' ||
      args.first == '-h') {
    _printUsage();
    return args.isEmpty ? 1 : 0;
  }

  // .g: subcommand dispatch.
  if (args.first == 'transform-file') {
    if (args.length < 2) {
      stderr.writeln('Usage: closure transform-file <path>');
      return 1;
    }
    return runTransformFile(args[1]);
  }

  String? paramName;
  final List<String> positional = <String>[];
  for (int i = 0; i < args.length; i++) {
    final String a = args[i];
    if (a == '--param' || a == '-p') {
      if (i + 1 < args.length) {
        paramName = args[i + 1];
        i++; // consume the next arg
      } else {
        stderr.writeln('Flag $a requires a value.');
        return 1;
      }
      continue;
    }
    if (a.startsWith('--param=')) {
      paramName = a.substring('--param='.length);
      continue;
    }
    if (a.startsWith('-p=')) {
      paramName = a.substring('-p='.length);
      continue;
    }
    positional.add(a);
  }

  if (positional.isEmpty) {
    stderr.writeln('Usage: closure <lambda_or_body> [--param <name>]');
    return 1;
  }

  final String input = positional.join(' ').trim();
  String body = input;
  if (paramName == null) {
    // Try to extract the param from a full lambda:
    // (t) => <body>
    final m = RegExp(r'^\(\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\)\s*=>\s*(.+)$')
        .firstMatch(input);
    if (m != null) {
      paramName = m.group(1);
      body = m.group(2)!;
    } else {
      stderr.writeln(
        'No --param supplied and the input does not look like a '
        'lambda (expected `(name) => body`).',
      );
      return 1;
    }
  }

  try {
    final String expr = translateClosureBody(body: body, paramName: paramName!);
    stdout.writeln(_kBanner);
    stdout.writeln('Input lambda: ($paramName) => $body');
    stdout.writeln('');
    stdout.writeln('Translated Expr:');
    stdout.writeln('  $expr');
    return 0;
  } on FormatException catch (e) {
    stderr.writeln('❌ Translation error: ${e.message}');
    return 1;
  }
}

void _printUsage() {
  stdout.writeln(_kBanner);
  stdout.writeln('''
Usage:
  closure <lambda_or_body> [--param <name>]

Examples:
  closure '(t) => t.status == 0'
  closure -p t 't.status == 0 && t.priority > 5'
  closure '(u) => u.name.toUpperCase()'
''');
}

// ─── CLI command: `transform-file <path>` ────────────────────

/// .g: process a file from the CLI. Reads
/// the source, runs [transformFileSource], and
/// writes the result back in-place (default) or to
/// `<path>.translated.dart` (with `—out`).
int runTransformFile(String path, {String? outPath}) {
  final File f = File(path);
  if (!f.existsSync()) {
    stderr.writeln('❌ File not found: $path');
    return 1;
  }
  final String source = f.readAsStringSync();
  final List<TransformReport> reports = <TransformReport>[];
  final String transformed = transformFileSource(source, reportSink: reports);
  final int rewrites = reports
      .where((TransformReport r) => r.status.startsWith('rewrote'))
      .length;
  final int skipped = reports
      .where((TransformReport r) => r.status.startsWith('skipped'))
      .length;
  final String target = outPath ?? path;
  f.writeAsStringSync(transformed);
  stdout.writeln('✅ Transformed $path → $target');
  stdout.writeln('   rewrites: $rewrites, skipped: $skipped');
  for (final TransformReport r in reports) {
    stdout.writeln('   L${r.line} ${r.method}: ${r.status}');
  }
  return 0;
}
