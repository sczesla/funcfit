import 'dart:math';

import 'package:funcfit/funcfit.dart';
import 'package:test/test.dart';

class _Line extends CurveModel {
  _Line({super.noise}) : super(["a", "b"]);

  @override
  List<double> evaluate(List<double> x) {
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }
}

/// Line with a fitted noise term: overrides lnL to pass the jitter.
class _JitterLine extends CurveModel {
  _JitterLine({super.noise}) : super(["a", "b", "jitter"]) {
    setBounds("jitter", 0, null);
  }

  @override
  List<double> evaluate(List<double> x) {
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }

  @override
  double lnL(XYData data) {
    final m = evaluate(data.x);
    final j = this["jitter"];
    return switch (noise) {
      Noise.gaussian => gaussianLnL(m, data.y, data.err, jitter: j),
      Noise.laplace => laplaceLnL(m, data.y, data.err, jitter: j),
    };
  }
}

/// Returns one value too few.
class _Broken extends CurveModel {
  _Broken() : super(["a"]);

  @override
  List<double> evaluate(List<double> x) => List.filled(x.length - 1, 0);
}

/// Standard normal random numbers (Box-Muller).
double _normal(Random r) =>
    sqrt(-2 * log(1 - r.nextDouble())) * cos(2 * pi * r.nextDouble());

/// Laplace random numbers with scale b.
double _laplace(Random r, double b) {
  final u = r.nextDouble() - 0.5;
  return -b * u.sign * log(1 - 2 * u.abs());
}

void main() {
  group('XYData', () {
    test('stores unmodifiable copies; err defaults to ones', () {
      final x = [1.0, 2.0, 3.0];
      final y = [4.0, 5.0];
      final d = XYData(x, y);
      x[0] = 99;
      y[0] = 99;
      expect(d.x, [1.0, 2.0, 3.0]);
      expect(d.y, [4.0, 5.0]);
      expect(d.err, isNull);
      expect(() => d.y[0] = 1, throwsUnsupportedError);
      expect(
          () => XYData(x, y, err: [1, 1]).err![0] = 2, throwsUnsupportedError);
    });

    test('err is copied before the check', () {
      final e = [0.5, 2.0];
      final d = XYData([0, 1], [1, 2], err: e);
      e[0] = 0; // invalid, must not reach the data
      expect(d.err, [0.5, 2.0]);
    });

    test('validates err', () {
      final x = [1.0, 2.0];
      final y = [1.0, 2.0];
      expect(() => XYData(x, y, err: [1.0]), throwsArgumentError);
      expect(() => XYData(x, y, err: [1.0, 0.0]), throwsArgumentError);
      expect(() => XYData(x, y, err: [1.0, -1.0]), throwsArgumentError);
      expect(() => XYData(x, y, err: [1.0, double.nan]), throwsArgumentError);
      expect(() => XYData(x, y, err: [1.0, double.negativeInfinity]),
          throwsArgumentError);
      expect(
          XYData(x, y, err: [1.0, double.infinity]).err![1], double.infinity);
    });
  });

  group('log-likelihoods', () {
    final y = [1.0, 2.0, 2.5];
    final err = [0.5, 1.0, 1.5];
    final model = [1.5, 1.5, 3.0];

    test('sums of log densities', () {
      double laplacePdf(double d, double b) => exp(-d.abs() / b) / (2 * b);
      double normalPdf(double d, double s) =>
          exp(-d * d / (2 * s * s)) / (sqrt(2 * pi) * s);
      double g = 0, l = 0;
      for (int i = 0; i < 3; i++) {
        g += log(normalPdf(model[i] - y[i], err[i]));
        l += log(laplacePdf(model[i] - y[i], err[i]));
      }
      expect(gaussianLnL(model, y, err), closeTo(g, 1e-12));
      expect(laplaceLnL(model, y, err), closeTo(l, 1e-12));
    });

    test('densities integrate to 1 (normalization), also with jitter', () {
      // Trapezoid integration of exp(lnL) over the model value, one point
      double integral(double Function(double) lnL, double scale) {
        const n = 200000;
        final lim = 30 * scale;
        final h = 2 * lim / n;
        double sum = 0;
        for (int i = 0; i <= n; i++) {
          final w = (i == 0 || i == n) ? 0.5 : 1.0;
          sum += w * exp(lnL(-lim + i * h));
        }
        return sum * h;
      }

      for (final j in [0.0, 0.4]) {
        expect(
            integral((m) => gaussianLnL([m], [0], [0.7], jitter: j), 0.7 + j),
            closeTo(1, 1e-6),
            reason: "Gaussian, jitter $j");
        expect(integral((m) => laplaceLnL([m], [0], [0.7], jitter: j), 0.7 + j),
            closeTo(1, 1e-6),
            reason: "Laplace, jitter $j");
      }
    });

    test('by hand', () {
      double g = 0, l = 0;
      for (int i = 0; i < 3; i++) {
        final d = model[i] - y[i];
        g += -0.5 * log(2 * pi) - log(err[i]) - d * d / (2 * err[i] * err[i]);
        l += -log(2 * err[i]) - d.abs() / err[i];
      }
      expect(gaussianLnL(model, y, err), closeTo(g, 1e-12));
      expect(laplaceLnL(model, y, err), closeTo(l, 1e-12));
    });

    test('infinite err is skipped', () {
      final e = [0.5, double.infinity, 1.5];
      final ref = [0, 2];
      double sub(double Function(List<double>, List<double>, List<double>) f) =>
          f([for (final i in ref) model[i]], [for (final i in ref) y[i]],
              [for (final i in ref) e[i]]);
      expect(gaussianLnL(model, y, e), closeTo(sub(gaussianLnL), 1e-12));
      expect(laplaceLnL(model, y, e), closeTo(sub(laplaceLnL), 1e-12));
    });

    test('no err: unit variance for both noise models', () {
      expect(gaussianLnL(model, y, null),
          gaussianLnL(model, y, List.filled(3, 1.0)));
      expect(laplaceLnL(model, y, null),
          laplaceLnL(model, y, List.filled(3, sqrt1_2)));
      expect(() => gaussianLnL([1.0], y, null), throwsArgumentError);
    });

    test('no err: the densities have variance 1', () {
      // Second moment of exp(lnL) over the residual, one point
      double variance(double Function(double) lnL) {
        const n = 400000, lim = 40.0, h = 2 * lim / n;
        double sum = 0;
        for (int i = 0; i <= n; i++) {
          final d = -lim + i * h;
          final w = (i == 0 || i == n) ? 0.5 : 1.0;
          sum += w * d * d * exp(lnL(d));
        }
        return sum * h;
      }

      expect(variance((d) => gaussianLnL([d], [0], null)), closeTo(1, 1e-6));
      expect(variance((d) => laplaceLnL([d], [0], null)), closeTo(1, 1e-6));
    });

    test('jitter adds in quadrature', () {
      const j = 0.7;
      final eff = [for (final e in err) sqrt(e * e + j * j)];
      expect(gaussianLnL(model, y, err, jitter: j),
          closeTo(gaussianLnL(model, y, eff), 1e-12));
      expect(laplaceLnL(model, y, err, jitter: j),
          closeTo(laplaceLnL(model, y, eff), 1e-12));
    });

    test('invalid input throws', () {
      for (final f in [gaussianLnL, laplaceLnL]) {
        expect(() => f([1.0], y, err), throwsArgumentError);
        expect(() => f(model, y, [1.0]), throwsArgumentError);
      }
      for (final j in [-0.1, double.nan, double.infinity]) {
        expect(() => gaussianLnL(model, y, err, jitter: j), throwsArgumentError,
            reason: "$j");
        expect(() => laplaceLnL(model, y, err, jitter: j), throwsArgumentError,
            reason: "$j");
      }
    });
  });

  group('CurveModel', () {
    final data =
        XYData([0, 1, 2, 3], [1.0, 2.8, 5.1, 7.0], err: [0.5, 0.5, 1.0, 1.0]);

    test('objective is -lnL for the chosen noise model', () {
      final g = _Line()
        ..["a"] = 1
        ..["b"] = 2;
      final l = _Line(noise: Noise.laplace)
        ..["a"] = 1
        ..["b"] = 2;
      final m = [1.0, 3.0, 5.0, 7.0];
      expect(g.objective(data), -gaussianLnL(m, data.y, data.err));
      expect(l.objective(data), -laplaceLnL(m, data.y, data.err));
      expect(g.lnL(data), -g.objective(data));
    });

    test('default noise is Gaussian; only the given parameters', () {
      expect(_Line().noise, Noise.gaussian);
      expect(_Line().params.names, ["a", "b"]);
    });

    test('lnL can be overridden for extra noise parameters', () {
      final m = _JitterLine()
        ..["a"] = 1
        ..["b"] = 2
        ..["jitter"] = 0.3;
      final model = [1.0, 3.0, 5.0, 7.0];
      expect(m.objective(data),
          -gaussianLnL(model, data.y, data.err, jitter: 0.3));
    });

    test('evaluate with the wrong length throws', () {
      expect(() => _Broken().objective(data), throwsArgumentError);
    });

    test('fitted jitter recovers Gaussian scatter', () async {
      final r = Random(1);
      final x = [for (int i = 0; i < 400; i++) i / 40];
      final y = [for (final xi in x) 1 + 0.5 * xi + 0.3 * _normal(r)];
      final m = _JitterLine();
      m["jitter"] = 0.1;
      final res = await fit(m, XYData(x, y, err: List.filled(400, 0.01)));
      expect(res.converged, isTrue);
      expect(m["jitter"], closeTo(0.3, 0.03));
      expect(m["b"], closeTo(0.5, 0.02));
    });

    test('fitted jitter recovers Laplace scale', () async {
      final r = Random(2);
      final x = [for (int i = 0; i < 400; i++) i / 40];
      final y = [for (final xi in x) 1 + 0.5 * xi + _laplace(r, 0.3)];
      final m = _JitterLine(noise: Noise.laplace);
      m["jitter"] = 0.1;
      final res = await fit(m, XYData(x, y, err: List.filled(400, 0.01)));
      expect(res.converged, isTrue);
      expect(m["jitter"], closeTo(0.3, 0.03));
    });

    test('no err: same fit as with constant err (Gaussian)', () async {
      // The scale of err only rescales and shifts the objective, so the
      // minimum is the same. Only checked for Gaussian noise: on the
      // non-smooth Laplace objective, Powell stops near but not exactly at
      // the minimum, at a point that depends on the scale. For Laplace, the
      // tests of laplaceLnL with err == null cover the change.
      final x = <double>[0, 1, 2, 3, 4, 5, 6, 7];
      final y = [1.2, 2.9, 5.3, 6.8, 9.4, 10.7, 13.1, 15.2];
      final a = _Line();
      final b = _Line();
      await fit(a, XYData(x, y));
      await fit(b, XYData(x, y, err: List.filled(8, 1.0)));
      expect(a["a"], closeTo(b["a"], 1e-6));
      expect(a["b"], closeTo(b["b"], 1e-6));
    });

    test('Laplace noise is robust against an outlier', () async {
      final x = <double>[0, 1, 2, 3, 4, 5, 6, 7];
      final y = [for (final xi in x) 1 + 2 * xi];
      y[6] += 30; // outlier
      final d = XYData(x, y);
      final g = _Line();
      final l = _Line(noise: Noise.laplace);
      await fit(g, d);
      await fit(l, d);
      expect((l["b"] - 2).abs(), lessThan(0.05));
      expect((g["b"] - 2).abs(), greaterThan(1));
    });
  });
}
