import 'package:funcfit/funcfit.dart';
import 'package:test/test.dart';

typedef _XY = ({List<double> x, List<double> y});

/// Straight line y = a + b x, least squares. Fails the test if evaluated
/// with parameter values outside the limits.
class _Line extends Model<_XY> {
  _Line() : super(["a", "b"]);

  int evaluations = 0;

  @override
  double objective(_XY d) {
    evaluations++;
    for (final p in params.parameters) {
      if ((p.lower != null && p.value < p.lower!) ||
          (p.upper != null && p.value > p.upper!)) {
        fail("Evaluated outside the limits: $params");
      }
    }
    final a = this["a"], b = this["b"];
    double chi2 = 0;
    for (int i = 0; i < d.x.length; i++) {
      final r = d.y[i] - (a + b * d.x[i]);
      chi2 += r * r;
    }
    return chi2;
  }
}

final _XY _data =
    (x: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0], y: [1.1, 2.9, 5.2, 6.8, 9.1, 11.0]);

/// Closed-form least-squares line for [_data].
({double a, double b}) _lsq() {
  final n = _data.x.length;
  double sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (int i = 0; i < n; i++) {
    sx += _data.x[i];
    sy += _data.y[i];
    sxx += _data.x[i] * _data.x[i];
    sxy += _data.x[i] * _data.y[i];
  }
  final b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
  return (a: (sy - b * sx) / n, b: b);
}

/// Fake minimizer returning a fixed point; records its arguments; can
/// throw after evaluating f, or refuse bounds.
/// Objective (a/per - 1)² + per²; NaN for a = per = 0.
class _Ratio extends Model<double> {
  _Ratio() : super(["a", "per"]);

  @override
  double objective(double data) {
    final q = this["a"] / this["per"] - 1;
    return q * q + this["per"] * this["per"] + data;
  }
}

class _FakeMinimizer implements Minimizer {
  _FakeMinimizer(this.answer,
      {this.throwAfterEvaluation = false, this.supportsBounds = true});

  final List<double> answer;
  final bool throwAfterEvaluation;
  final bool supportsBounds;
  List<double>? x0;
  List<double?>? lower;
  List<double?>? upper;

  @override
  Future<MinimizerResult> minimize(
      double Function(List<double>) f, List<double> x0,
      {List<double?>? lower, List<double?>? upper}) async {
    if (!supportsBounds && (lower != null || upper != null)) {
      throw ArgumentError("Bounds are not supported");
    }
    this.x0 = List.of(x0);
    this.lower = lower;
    this.upper = upper;
    if (throwAfterEvaluation) {
      f([for (final v in x0) v + 100]);
      throw StateError("minimizer failed");
    }
    return _FakeResult(answer, f(answer));
  }
}

class _FakeResult implements MinimizerResult {
  _FakeResult(this.value, this.objective);
  @override
  final List<double> value;
  @override
  final double objective;
  @override
  bool get converged => true;
  @override
  String get message => "fake";
  @override
  int get evaluations => 1;
}

void main() {
  group('Model', () {
    test('pass-through methods act on params', () {
      final m = _Line();
      m["a"] = 2;
      expect(m.params["a"], 2);
      expect(m["a"], 2);
      m.freeze("a");
      expect(m.params.parameter("a").state, ParameterState.frozen);
      m.thaw("a");
      expect(m.params.parameter("a").state, ParameterState.free);
      m.setLimits("b", 0, 1);
      expect(m.params.parameter("b").upper, 1);
      m.setLimits("b", null, null);
      m.relate("b", ["a"], (v) => 3 * v[0]);
      expect(m["b"], 6);
      m.removeRelation("b");
      expect(m.params.parameter("b").state, ParameterState.free);
      expect(m.toString(), startsWith("_Line: a = 2.0"));
    });
  });

  group('fit with Powell', () {
    test('all parameters free: least-squares solution', () async {
      final m = _Line();
      final r = await fit(m, _data);
      final e = _lsq();
      expect(r.converged, isTrue);
      expect(m["a"], closeTo(e.a, 1e-4));
      expect(m["b"], closeTo(e.b, 1e-4));
      expect(r.values, {"a": m["a"], "b": m["b"]});
      expect(r.objective, closeTo(m.objective(_data), 1e-12));
      expect(r.minimizerResult, isA<PowellResult>());
    });

    test('frozen parameter keeps its value', () async {
      final m = _Line();
      m.freeze("a"); // line through the origin
      await fit(m, _data);
      double sxy = 0, sxx = 0;
      for (int i = 0; i < _data.x.length; i++) {
        sxy += _data.x[i] * _data.y[i];
        sxx += _data.x[i] * _data.x[i];
      }
      expect(m["a"], 0);
      expect(m["b"], closeTo(sxy / sxx, 1e-4));
    });

    test('limits act as bounds; never evaluated outside', () async {
      final m = _Line();
      m.setLimits("b", null, 1.5); // unconstrained b is about 2
      final r = await fit(m, _data);
      expect(r.converged, isTrue);
      expect(m["b"], 1.5);
    });

    test('dependent parameter follows its relation', () async {
      // a = 2 b, i.e., y = b (2 + x)
      final m = _Line();
      m.relate("a", ["b"], (v) => 2 * v[0], description: "2 b");
      final r = await fit(m, _data);
      double num = 0, den = 0;
      for (int i = 0; i < _data.x.length; i++) {
        final u = 2 + _data.x[i];
        num += u * _data.y[i];
        den += u * u;
      }
      expect(m["b"], closeTo(num / den, 1e-4));
      expect(m["a"], 2 * m["b"]);
      expect(r.values["a"], m["a"]);
    });

    test('sequential fits: freeze, fit, thaw, fit', () async {
      final m = _Line();
      m["a"] = 5;
      m.freeze("a");
      await fit(m, _data);
      expect(m["a"], 5);
      m.thaw("a");
      await fit(m, _data);
      final e = _lsq();
      expect(m["a"], closeTo(e.a, 1e-4));
      expect(m["b"], closeTo(e.b, 1e-4));
    });

    test('Powell options are passed through', () async {
      final m = _Line();
      int calls = 0;
      final r = await fit(m, _data,
          minimizer: Powell(
              maxEvaluations: 5,
              onIteration: (_) {
                calls++;
                return true;
              }));
      expect((r.minimizerResult as PowellResult).status,
          PowellStatus.maxEvaluationsReached);
      expect(r.converged, isFalse);
      expect(calls, 0);
    });
  });

  group('fit checks', () {
    test('objective NaN at the start values throws, naming the values',
        () async {
      final m = _Ratio(); // a and per start at 0: 0/0
      await expectLater(
          fit(m, 0.0),
          throwsA(isA<ArgumentError>().having(
              (e) => e.message, "message", contains("a = 0.0, per = 0.0"))));
      expect(m["per"], 0);
      m["per"] = 1;
      final r = await fit(m, 0.0);
      expect(r.converged, isTrue);
    });

    test('start value outside the limits throws before evaluating', () async {
      final m = _Line();
      m["b"] = 3;
      m.setLimits("b", 0, 2);
      await expectLater(fit(m, _data), throwsArgumentError);
      expect(m.evaluations, 0);
    });

    test('relation source outside the model throws', () async {
      final m = _Line();
      final other = ParameterSet(["x"]);
      m.params.parameter("a").relate([other.parameter("x")], (v) => v[0]);
      await expectLater(fit(m, _data), throwsArgumentError);
    });

    test('no free parameters throws', () async {
      final m = _Line();
      m.freeze("a");
      m.freeze("b");
      await expectLater(fit(m, _data), throwsArgumentError);
    });
  });

  group('fit with a fake minimizer', () {
    test('start values, bounds, and write-back', () async {
      final m = _Line();
      m["a"] = 1;
      m["b"] = 2;
      m.setLimits("b", 0, 10);
      final fake = _FakeMinimizer([3, 4]);
      final r = await fit(m, _data, minimizer: fake);
      expect(fake.x0, [1.0, 2.0]);
      expect(fake.lower, [null, 0.0]);
      expect(fake.upper, [null, 10.0]);
      expect(m["a"], 3);
      expect(m["b"], 4);
      expect(r.values, {"a": 3.0, "b": 4.0});
      expect(r.message, "fake");
    });

    test('no limits: no bounds passed', () async {
      final fake = _FakeMinimizer([0, 0]);
      await fit(_Line(), _data, minimizer: fake);
      expect(fake.lower, isNull);
      expect(fake.upper, isNull);
    });

    test(
        'minimizer without bounds support: fine without limits, '
        'throws with limits', () async {
      final m = _Line();
      await fit(m, _data,
          minimizer: _FakeMinimizer([1, 1], supportsBounds: false));
      m.setLimits("a", 0, null);
      await expectLater(
          fit(m, _data,
              minimizer: _FakeMinimizer([1, 1], supportsBounds: false)),
          throwsArgumentError);
    });

    test('start values are restored if the minimizer throws', () async {
      final m = _Line();
      m["a"] = 1;
      m["b"] = 2;
      m.relate("a", ["b"], (v) => v[0] / 2);
      await expectLater(
          fit(m, _data,
              minimizer: _FakeMinimizer([0], throwAfterEvaluation: true)),
          throwsStateError);
      expect(m.evaluations, 2); // start check of fit() + minimizer
      expect(m["b"], 2);
      expect(m["a"], 1);
    });
  });
}
