// Compiles and runs the Dart code blocks of README.md that contain a main
// function, so that the documentation cannot go stale
// unnoticed. Blocks without main (e.g., import listings) are skipped.

import 'dart:io';

import 'package:test/test.dart';

/// Dart code blocks (```dart ... ```) of the Markdown file [path].
List<String> _dartBlocks(String path) =>
    RegExp(r'```dart\n(.*?)```', dotAll: true)
        .allMatches(File(path).readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();

void main() {
  // Inside the package, so that package:funcfit resolves; .dart_tool is
  // ignored by git and the analyzer
  final dir = Directory('.dart_tool/doc_snippets');

  setUpAll(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
  });

  for (final doc in ['README.md']) {
    final blocks = _dartBlocks(doc);
    for (int i = 0; i < blocks.length; i++) {
      final code = blocks[i];
      if (!code.contains(RegExp(r'\bmain\s*\('))) continue;
      test('$doc, code block ${i + 1} runs', () async {
        final name = doc.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
        final file = File('${dir.path}/${name}_$i.dart')
          ..writeAsStringSync(code);
        final r =
            await Process.run(Platform.resolvedExecutable, ['run', file.path]);
        expect(r.exitCode, 0,
            reason: 'Code block ${i + 1} of $doc failed:\n${r.stdout}\n'
                '${r.stderr}');
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  }
}
