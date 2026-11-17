// Randomized check of powell() with bounds against the optimality (KKT)
// conditions for box constraints: at a local minimum, the gradient
// component of a parameter is
//   ~ 0  if the parameter is strictly inside its bounds,
//   >= 0 if the parameter is at its lower bound,
//   <= 0 if the parameter is at its upper bound.
// The violation of these conditions (the "projected gradient") must be
// small for every problem.

import 'dart:math';

import 'package:funcfit/minimize.dart';
import 'package:test/test.dart';

/// A bounded minimization problem.
class _Problem {
  _Problem(this.name, this.f, this.lower, this.upper, this.start,
      {required this.gradientScale});

  final String name;
  final double Function(List<double>) f;
  final List<double?> lower;
  final List<double?> upper;
  final List<double> start;

  /// Typical gradient magnitude, to make the tolerance relative.
  final double gradientScale;

  int get n => start.length;

  @override
  String toString() => "$name, lower = $lower, upper = $upper, "
      "start = $start";
}

/// Central-difference gradient. The test functions are defined everywhere,
/// so evaluating slightly outside the bounds is fine here.
List<double> _gradient(double Function(List<double>) f, List<double> x) {
  final g = <double>[];
  for (int i = 0; i < x.length; i++) {
    final h = 1e-6 * max(1.0, x[i].abs());
    final xp = List.of(x)..[i] += h;
    final xm = List.of(x)..[i] -= h;
    g.add((f(xp) - f(xm)) / (2 * h));
  }
  return g;
}

/// Largest violation of the KKT conditions at [x]. A parameter within
/// [boundTol] of a bound counts as being at that bound.
double _kktViolation(_Problem p, List<double> x, {double boundTol = 1e-7}) {
  final g = _gradient(p.f, x);
  double worst = 0;
  for (int i = 0; i < p.n; i++) {
    final lo = p.lower[i];
    final hi = p.upper[i];
    final atLower = lo != null && x[i] - lo <= boundTol;
    final atUpper = hi != null && hi - x[i] <= boundTol;
    double v;
    if (atLower && atUpper) {
      v = 0; // fixed by (nearly) equal bounds
    } else if (atLower) {
      v = max(0, -g[i]);
    } else if (atUpper) {
      v = max(0, g[i]);
    } else {
      v = g[i].abs();
    }
    worst = max(worst, v);
  }
  return worst;
}

double _uniform(Random r, double a, double b) => a + (b - a) * r.nextDouble();

/// Random box: some parameters unbounded, some bounded on one side only.
/// The start point is drawn uniformly from the box (or from [-3, 3] on
/// unbounded sides).
({List<double?> lower, List<double?> upper, List<double> start}) _randomBox(
    Random r, int n) {
  final lower = <double?>[];
  final upper = <double?>[];
  final start = <double>[];
  for (int i = 0; i < n; i++) {
    double? lo;
    double? hi;
    final kind = r.nextDouble();
    if (kind < 0.15) {
      // unbounded
    } else if (kind < 0.3) {
      lo = _uniform(r, -2, 1);
    } else if (kind < 0.45) {
      hi = _uniform(r, -1, 2);
    } else {
      lo = _uniform(r, -2, 1);
      hi = lo + _uniform(r, 0.2, 3);
    }
    lower.add(lo);
    upper.add(hi);
    final a = lo ?? min(-3.0, (hi ?? 0) - 3);
    final b = hi ?? max(3.0, (lo ?? 0) + 3);
    start.add(_uniform(r, a, b));
  }
  return (lower: lower, upper: upper, start: start);
}

/// Random orthogonal matrix (Gram-Schmidt of a random matrix).
List<List<double>> _randomRotation(Random r, int n) {
  final q = <List<double>>[];
  while (q.length < n) {
    var v = List.generate(n, (_) => _uniform(r, -1, 1));
    for (final u in q) {
      double d = 0;
      for (int k = 0; k < n; k++) {
        d += v[k] * u[k];
      }
      v = [for (int k = 0; k < n; k++) v[k] - d * u[k]];
    }
    final norm = sqrt(v.fold(0.0, (s, e) => s + e * e));
    if (norm < 1e-6) continue;
    q.add([for (final e in v) e / norm]);
  }
  return q;
}

/// f(x) = 1/2 (x - c)^T R^T D R (x - c), condition number up to 100.
_Problem _rotatedQuadratic(Random r, int seed) {
  final n = 2 + r.nextInt(4);
  final rot = _randomRotation(r, n);
  final d = List.generate(n, (_) => pow(10, _uniform(r, 0, 2)).toDouble());
  final c = List.generate(n, (_) => _uniform(r, -2, 2));
  double f(List<double> x) {
    double s = 0;
    for (int i = 0; i < n; i++) {
      double y = 0;
      for (int k = 0; k < n; k++) {
        y += rot[i][k] * (x[k] - c[k]);
      }
      s += d[i] * y * y;
    }
    return 0.5 * s;
  }

  final box = _randomBox(r, n);
  return _Problem(
      "quadratic #$seed (n = $n)", f, box.lower, box.upper, box.start,
      gradientScale: d.reduce(max));
}

/// Extended Rosenbrock function, minimum at (1, ..., 1) without bounds.
_Problem _rosenbrock(Random r, int seed) {
  final n = 2 + r.nextInt(3);
  double f(List<double> x) {
    double s = 0;
    for (int i = 0; i < n - 1; i++) {
      s += 100 * pow(x[i + 1] - x[i] * x[i], 2) + pow(1 - x[i], 2);
    }
    return s;
  }

  final box = _randomBox(r, n);
  return _Problem(
      "Rosenbrock #$seed (n = $n)", f, box.lower, box.upper, box.start,
      gradientScale: 100);
}

/// Runs [count] random problems from [make] and expects all of them to
/// satisfy the KKT conditions to a relative tolerance [tol].
Future<void> _check(_Problem Function(Random, int) make, int count,
    {double tol = 1e-6}) async {
  final failures = <String>[];
  for (int seed = 0; seed < count; seed++) {
    final p = make(Random(seed), seed);
    final res = await powell(p.f, p.start,
        lowerBounds: p.lower,
        upperBounds: p.upper,
        rftol: 1e-12,
        aftol: 1e-14,
        xtol: 1e-8,
        maxIterations: 1000);
    // Never outside the bounds
    for (int i = 0; i < p.n; i++) {
      expect(res.value[i], greaterThanOrEqualTo(p.lower[i] ?? -1 / 0),
          reason: "$p");
      expect(res.value[i], lessThanOrEqualTo(p.upper[i] ?? 1 / 0),
          reason: "$p");
    }
    final v = _kktViolation(p, res.value) / p.gradientScale;
    if (!(v <= tol)) {
      failures.add("$p\n    -> ${res.value}, f = ${res.objective}, "
          "${res.status.name}, relative KKT violation = $v");
    }
  }
  expect(failures, isEmpty,
      reason: "${failures.length} of $count problems violate the KKT "
          "conditions:\n${failures.join('\n')}");
}

void main() {
  group('powell with random bounds satisfies the KKT conditions', () {
    test('rotated quadratics', () => _check(_rotatedQuadratic, 200));
    test('extended Rosenbrock', () => _check(_rosenbrock, 200));
  });
}
