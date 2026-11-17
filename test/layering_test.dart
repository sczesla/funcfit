// The minimization algorithms (lib/src/minimize, lib/minimize.dart) must not
// depend on the parameter and model layer (lib/src/paramfit), so that they
// stay usable on their own and could be split into a separate package.

import 'dart:io';

import 'package:test/test.dart';

/// Import, export, and part directives of a Dart file.
Iterable<String> _directives(File f) =>
    RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
            multiLine: true)
        .allMatches(f.readAsStringSync())
        .map((m) => m.group(1)!);

void main() {
  test('minimize does not depend on paramfit', () {
    final files = [
      File('lib/minimize.dart'),
      ...Directory('lib/src/minimize')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
    ];
    expect(files.length, greaterThan(1));
    for (final f in files) {
      for (final uri in _directives(f)) {
        expect(uri, isNot(contains('paramfit')),
            reason: '${f.path} refers to $uri');
        expect(uri, isNot(equals('funcfit.dart')),
            reason: '${f.path} refers to $uri');
        expect(uri, isNot(contains('package:funcfit/funcfit.dart')),
            reason: '${f.path} refers to $uri');
      }
    }
  });
}
