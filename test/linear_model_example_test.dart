import 'package:funcfit/funcfit.dart';
import 'package:test/test.dart';

import '../example/funcfit_example.dart';
import '../example/funcfit_example.dart' as example;

// Reference values: closed-form (weighted) least-squares solutions
void main() {
  final x = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
  final y = [0.1, 1.9, 3.5, 4.1, 4.4, 6.1];

  test('a and b free: ordinary least squares', () async {
    final line = Line();
    final r = await fit(line, XYData(x, y));
    expect(r.converged, isTrue);
    expect(line["a"], closeTo(-0.46, 1e-3));
    expect(line["b"], closeTo(1.0885714, 1e-3));
    expect(r.values, {"a": line["a"], "b": line["b"]});
  });

  test('a frozen at 0: line through the origin', () async {
    final line = Line();
    line["a"] = 0.0;
    line.freeze("a");
    final r = await fit(line, XYData(x, y));
    expect(r.converged, isTrue);
    // b = sum(x*y) / sum(x^2)
    expect(line["b"], closeTo(0.9824176, 1e-3));
    expect(line["a"], equals(0.0));
  });

  test('with errors: weighted least squares (weights 1/err^2)', () async {
    final e = [0.1, 0.1, 1.0, 2.0, 0.1, 0.1];
    final line = Line();
    final r = await fit(line, XYData(x, y, err: e));
    expect(r.converged, isTrue);
    expect(line["a"], closeTo(-0.7318789, 1e-3));
    expect(line["b"], closeTo(1.1027004, 1e-3));
  });

  test('example main runs', () => example.main());
}
