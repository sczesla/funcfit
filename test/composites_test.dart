import 'dart:math';

import 'package:funcfit/funcfit.dart';
import 'package:test/test.dart';

class _Line extends CurveModel {
  _Line() : super(["a", "b"]);

  @override
  List<double> evaluate(List<double> x) {
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }
}

class _Gaussian extends CurveModel {
  _Gaussian() : super(["amp", "mu", "sigma"]);

  @override
  List<double> evaluate(List<double> x) {
    final amp = this["amp"], mu = this["mu"], sigma = this["sigma"];
    return [
      for (final xi in x)
        amp * exp(-(xi - mu) * (xi - mu) / (2 * sigma * sigma))
    ];
  }
}

/// Transmission 1 - depth·exp(...): an absorption line, no free scale.
class _Absorption extends CurveModel {
  _Absorption() : super(["depth", "mu", "sigma"]);

  @override
  List<double> evaluate(List<double> x) {
    final depth = this["depth"], mu = this["mu"], sigma = this["sigma"];
    return [
      for (final xi in x)
        1 - depth * exp(-(xi - mu) * (xi - mu) / (2 * sigma * sigma))
    ];
  }
}

/// Returns one value too few.
class _Short extends CurveModel {
  _Short() : super(["c"]);

  @override
  List<double> evaluate(List<double> x) => List.filled(x.length - 1, 0);
}

/// Line plus two Gaussian peaks, with small deterministic "noise".
XYData _data() {
  final x = [for (int i = 0; i <= 200; i++) i / 20];
  final y = [
    for (final xi in x)
      0.5 +
          0.2 * xi +
          3 * exp(-(xi - 3) * (xi - 3) / (2 * 0.4 * 0.4)) +
          2 * exp(-(xi - 7) * (xi - 7) / (2 * 0.4 * 0.4)) +
          0.01 * sin(37 * xi)
  ];
  return XYData(x, y, err: List.filled(x.length, 0.01));
}

({_Line line, _Gaussian g1, _Gaussian g2, CurveSum sum}) _model() {
  final line = _Line();
  final g1 = _Gaussian();
  final g2 = _Gaussian();
  line.params.setValues({"a": 0.3, "b": 0.25});
  g1.params.setValues({"amp": 2.5, "mu": 2.8, "sigma": 0.5});
  g2.params.setValues({"amp": 1.5, "mu": 7.2, "sigma": 0.5});
  final sum = CurveSum({"line": line, "g1": g1, "g2": g2});
  return (line: line, g1: g1, g2: g2, sum: sum);
}

void main() {
  group('CurveSum structure', () {
    test('evaluate is the sum of the components', () {
      final m = _model();
      final x = [0.0, 2.5, 3.0, 9.0];
      final expected = [
        for (int i = 0; i < x.length; i++)
          m.line.evaluate(x)[i] + m.g1.evaluate(x)[i] + m.g2.evaluate(x)[i]
      ];
      final got = m.sum.evaluate(x);
      for (int i = 0; i < x.length; i++) {
        expect(got[i], closeTo(expected[i], 1e-12));
      }
    });

    test('qualified names, order, and views on the components', () {
      final m = _model();
      expect(m.sum.params.names, [
        "line.a", "line.b", //
        "g1.amp", "g1.mu", "g1.sigma", //
        "g2.amp", "g2.mu", "g2.sigma"
      ]);
      m.sum["g1.mu"] = 4;
      expect(m.g1["mu"], 4);
      m.g2["amp"] = 9;
      expect(m.sum["g2.amp"], 9);
      expect(m.sum.components.keys, ["line", "g1", "g2"]);
      expect(() => m.sum.components["x"] = m.line, throwsUnsupportedError);
    });

    test('noise model of the sum applies', () {
      final line = _Line()..["a"] = 1;
      final sum = CurveSum({"line": line}, noise: Noise.laplace);
      final d = XYData([0.0, 1.0], [2.0, 3.0]);
      expect(sum.objective(d), -laplaceLnL([1, 1], d.y, d.err));
    });

    test('nested sums', () {
      final line = _Line();
      final inner = CurveSum({"line": line});
      final outer = CurveSum({"inner": inner, "g": _Gaussian()});
      expect(outer.params.names.first, "inner.line.a");
      outer["inner.line.b"] = 2;
      expect(line["b"], 2);
      line["a"] = 1;
      outer.params.setValues({"g.amp": 0});
      expect(outer.evaluate([3.0]).single, 7);
    });

    test('invalid constructions throw', () {
      final line = _Line();
      expect(() => CurveSum({}), throwsArgumentError);
      expect(() => CurveSum({"a.b": _Line()}), throwsArgumentError);
      expect(() => CurveSum({"": _Line()}), throwsArgumentError);
      // Same component twice, also nested
      expect(() => CurveSum({"x": line, "y": line}), throwsArgumentError);
      expect(
          () => CurveSum({
                "x": line,
                "s": CurveSum({"l": line})
              }),
          throwsArgumentError);
    });

    test('curves of different lengths throw', () {
      final sum = CurveSum({"line": _Line(), "short": _Short()});
      expect(() => sum.evaluate([1.0, 2.0]), throwsArgumentError);
    });
  });

  group('fitting a CurveSum', () {
    test('line plus two peaks; components hold the best fit', () async {
      final m = _model();
      final r = await fit(m.sum, _data(),
          minimizer: const Powell(rftol: 1e-10, aftol: 1e-8, xtol: 1e-6));
      expect(r.converged, isTrue);
      expect(m.line["a"], closeTo(0.5, 0.01));
      expect(m.line["b"], closeTo(0.2, 0.01));
      expect(m.g1["amp"], closeTo(3, 0.01));
      expect(m.g1["mu"], closeTo(3, 0.01));
      expect(m.g2["mu"], closeTo(7, 0.01));
      expect(m.g2["sigma"].abs(), closeTo(0.4, 0.01));
      expect(r.values["g1.mu"], m.g1["mu"]);
    });

    test('relation across components and frozen parameters', () async {
      final m = _model();
      // Both peaks have the same width; slope fixed at its true value
      m.sum.relate("g2.sigma", ["g1.sigma"], (v) => v[0]);
      m.sum["line.b"] = 0.2;
      m.sum.freeze("line.b");
      final r = await fit(m.sum, _data(),
          minimizer: const Powell(rftol: 1e-10, aftol: 1e-8, xtol: 1e-6));
      expect(r.converged, isTrue);
      expect(r.minimizerResult.value, hasLength(6));
      expect(m.g2["sigma"], m.g1["sigma"]);
      expect(m.g1["sigma"].abs(), closeTo(0.4, 0.01));
      expect(m.line["b"], 0.2);
    });

    test('limits on component parameters act as bounds', () async {
      final m = _model();
      m.sum.setLimits("g1.amp", 0, 2); // true value 3
      // Start value 2.5 outside the limits: rejected, qualified name given
      await expectLater(
          fit(m.sum, _data()),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, "message", contains("'g1.amp'"))));
      m.sum["g1.amp"] = 1.5;
      final r = await fit(m.sum, _data());
      expect(m.g1["amp"], lessThanOrEqualTo(2));
      expect(m.g1["amp"], closeTo(2, 1e-9));
      expect(r.values["g1.amp"], m.g1["amp"]);
    });
  });

  group('CurveProduct', () {
    test('evaluate is the product of the components', () {
      final line = _Line()..params.setValues({"a": 0.5, "b": 0.2});
      final abs = _Absorption()
        ..params.setValues({"depth": 0.6, "mu": 5, "sigma": 0.5});
      final prod = CurveProduct({"line": line, "abs": abs});
      final x = [0.0, 4.5, 5.0, 9.0];
      final got = prod.evaluate(x);
      for (int i = 0; i < x.length; i++) {
        expect(
            got[i], closeTo(line.evaluate(x)[i] * abs.evaluate(x)[i], 1e-12));
      }
      expect(prod.params.names,
          ["line.a", "line.b", "abs.depth", "abs.mu", "abs.sigma"]);
      expect(prod.components.keys, ["line", "abs"]);
    });

    test('nested with CurveSum in both directions', () {
      final line = _Line()..params.setValues({"a": 1, "b": 0});
      final g = _Gaussian()..params.setValues({"amp": 2, "mu": 0, "sigma": 1});
      final abs = _Absorption()
        ..params.setValues({"depth": 0.5, "mu": 0, "sigma": 1});
      // (1 + 2) * 0.5 at x = 0
      final prod = CurveProduct({
        "src": CurveSum({"line": line, "g": g}),
        "abs": abs
      });
      expect(prod.evaluate([0.0]).single, closeTo(1.5, 1e-12));
      expect(prod.params.names.first, "src.line.a");
      // 1 + 1.5 at x = 0
      final c = _Line()..params.setValues({"a": 1, "b": 0});
      final sum = CurveSum({"c": c, "p": prod});
      expect(sum.evaluate([0.0]).single, closeTo(2.5, 1e-12));
      sum["p.abs.depth"] = 0;
      expect(abs["depth"], 0);
    });

    test('invalid constructions throw', () {
      final line = _Line();
      expect(() => CurveProduct({}), throwsArgumentError);
      expect(() => CurveProduct({"a.b": _Line()}), throwsArgumentError);
      expect(() => CurveProduct({"x": line, "y": line}), throwsArgumentError);
      final prod = CurveProduct({"line": _Line(), "short": _Short()});
      expect(() => prod.evaluate([1.0, 2.0]), throwsArgumentError);
    });

    test('noise model of the product applies', () {
      final line = _Line()..["a"] = 1;
      final prod = CurveProduct({"line": line}, noise: Noise.laplace);
      final d = XYData([0.0, 1.0], [2.0, 3.0]);
      expect(prod.objective(d), -laplaceLnL([1, 1], d.y, d.err));
    });

    test('fit: continuum times absorption line', () async {
      final x = [for (int i = 0; i <= 200; i++) i / 20];
      final y = [
        for (final xi in x)
          (0.5 + 0.2 * xi) *
                  (1 - 0.6 * exp(-(xi - 5) * (xi - 5) / (2 * 0.5 * 0.5))) +
              0.01 * sin(37 * xi)
      ];
      final data = XYData(x, y, err: List.filled(x.length, 0.01));
      final line = _Line()..params.setValues({"a": 0.4, "b": 0.25});
      final abs = _Absorption()
        ..params.setValues({"depth": 0.4, "mu": 4.8, "sigma": 0.7});
      final prod = CurveProduct({"line": line, "abs": abs});
      final r = await fit(prod, data,
          minimizer: const Powell(rftol: 1e-10, aftol: 1e-8, xtol: 1e-6));
      expect(r.converged, isTrue);
      expect(line["a"], closeTo(0.5, 0.01));
      expect(line["b"], closeTo(0.2, 0.01));
      expect(abs["depth"], closeTo(0.6, 0.01));
      expect(abs["mu"], closeTo(5, 0.01));
      expect(abs["sigma"].abs(), closeTo(0.5, 0.01));
    });
  });
}
