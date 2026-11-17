import 'package:test/test.dart';
import 'package:funcfit/minimize.dart';
import 'dart:math';

void main() {
  group("Powell's method section", () {
    test('one', () async {
      double f(List<double> p) {
        return (pow(p[0], 2) + pow(p[1], 2)).toDouble();
      }

      List<double> p0 = [1.5, -12.3];
      PowellResult p = await powell(f, p0);
      print(p);
    });

    test('two', () async {
      double f(List<double> p) {
        return (pow(p[0], 2) + pow(p[1], 2) + 10 + pow(p[2] - 5, 4)).toDouble();
      }

      List<double> p0 = [1.5, -12.3, 1];
      PowellResult p = await powell(f, p0);
      print(p);
    });

    // Regression: the line search used to start at the current coordinate
    // value instead of step length 0. With coordinates far from 0, the
    // bracket search failed and Powell "converged" without moving.
    test('minimum far from origin', () async {
      double f(List<double> p) {
        return (pow(p[0] - 1001, 2) + pow(p[1] + 2003, 2)).toDouble();
      }

      PowellResult p = await powell(f, [1000, -2000]);
      expect(p.converged, isTrue);
      expect(p.value[0], closeTo(1001, 1e-2));
      expect(p.value[1], closeTo(-2003, 1e-2));
      expect(p.objective, lessThan(1e-4));
    });

    test('line search does not move to a worse point', () async {
      // Start at the minimum; the result must stay there
      double f(List<double> p) {
        return (pow(p[0] - 1000, 2) + pow(p[1] - 1000, 2)).toDouble();
      }

      PowellResult p = await powell(f, [1000, 1000]);
      expect(p.converged, isTrue);
      expect(p.value[0], closeTo(1000, 1e-2));
      expect(p.value[1], closeTo(1000, 1e-2));
      expect(p.objective, lessThan(1e-4));
    });

    // No. 2: a failed line search must not be reported as convergence
    test('unbounded objective is not reported as converged', () async {
      double f(List<double> p) => p[0];
      PowellResult p = await powell(f, [0], maxIterations: 10);
      expect(p.converged, isFalse);
      expect(p.objective, lessThan(-1));
      expect(p.objective, equals(f(p.value)));
    });

    // No. 2: minimum beyond the reach of a single bracket search
    test('minimum requiring a large step is found', () async {
      double f(List<double> p) {
        return (pow(p[0] - 1, 2) + pow(p[1] + 250, 2)).toDouble();
      }

      PowellResult p = await powell(f, [0, 5]);
      expect(p.converged, isTrue);
      expect(p.value[0], closeTo(1, 1e-2));
      expect(p.value[1], closeTo(-250, 1e-2));
    });

    // No. 2: a flat direction (line search cannot bracket, but nothing to
    // gain) must not prevent convergence
    test('flat direction does not prevent convergence', () async {
      double f(List<double> p) => pow(p[0] - 3, 2).toDouble();
      PowellResult p = await powell(f, [0, 7]);
      expect(p.converged, isTrue);
      expect(p.value[0], closeTo(3, 1e-2));
      expect(p.value[1], equals(7));
    });

    // No. 3: best point is returned if maxIterations is reached
    test('maxIterations returns best point found', () async {
      // Rosenbrock function; needs many iterations from this start
      double f(List<double> p) =>
          (pow(1 - p[0], 2) + 100 * pow(p[1] - p[0] * p[0], 2)).toDouble();
      List<double> start = [-1.2, 1.0];
      PowellResult p = await powell(f, start, maxIterations: 1);
      expect(p.converged, isFalse);
      expect(p.iterations, equals(1));
      expect(p.objective, equals(f(p.value)));
      expect(p.objective, lessThan(f(start)));
    });

    // No. 3: stateful objectives are left at the returned point
    test('objective is last evaluated at the returned point', () async {
      List<double>? lastArgs;
      double f(List<double> p) {
        lastArgs = List.of(p);
        return (pow(p[0] - 2, 2) + pow(p[1] + 1, 2)).toDouble();
      }

      PowellResult p = await powell(f, [0, 0]);
      expect(lastArgs, equals(p.value));
    });

    // No. 4: zero objective at the start with only the relative criterion
    test('relative criterion works with zero objective', () async {
      double f(List<double> p) => (p[0] * p[0]).toDouble();
      PowellResult p = await powell(f, [0], aftol: 0, maxIterations: 5);
      expect(p.converged, isTrue);
      expect(p.message, contains("Relative"));
      expect(p.value[0], closeTo(0, 1e-3));
    });

    test('relative criterion with negative minimum', () async {
      double f(List<double> p) =>
          (pow(p[0] - 1, 2) + pow(p[1] + 2, 2) - 5).toDouble();
      PowellResult p = await powell(f, [4, 4], aftol: 0);
      expect(p.converged, isTrue);
      expect(p.objective, closeTo(-5, 1e-4));
    });

    test('objective receives a read-only list', () async {
      double f(List<double> p) {
        p[0] = 0; // must not be able to change Powell's internal point
        return p[0] * p[0];
      }

      expect(powell(f, [1.0]), throwsUnsupportedError);
    });

    test('result value is a modifiable copy', () async {
      double f(List<double> p) => (p[0] - 2) * (p[0] - 2);
      final r = await powell(f, [0.0]);
      r.value[0] = 99;
      expect(r.value[0], 99);
    });

    // No. 5: input validation
    test('invalid arguments throw', () {
      double f(List<double> p) => p[0] * p[0];
      expect(() => powell(f, []), throwsArgumentError);
      expect(() => powell(f, [1.0, 2.0], initialScale: [1.0]),
          throwsArgumentError);
      expect(() => powell(f, [1.0, 2.0], initialScale: [1.0, 0.0]),
          throwsArgumentError);
    });

    test('invalid maxEvaluations and xtol throw', () {
      double f(List<double> p) => p[0] * p[0];
      expect(() => powell(f, [1.0], maxEvaluations: 0), throwsArgumentError);
      for (final bad in [0.0, -1e-4, double.nan, double.infinity]) {
        expect(() => powell(f, [1.0], xtol: bad), throwsArgumentError,
            reason: "xtol = $bad");
      }
    });

    test('initialScale is used', () async {
      double f(List<double> p) =>
          (pow(p[0] - 0.01, 2) + pow(p[1] - 300, 2)).toDouble();
      PowellResult p = await powell(f, [0, 0], initialScale: [0.001, 100]);
      expect(p.converged, isTrue);
      expect(p.value[0], closeTo(0.01, 1e-3));
      expect(p.value[1], closeTo(300, 1e-2));
    });
  });

  group('status, evaluations, maxEvaluations, xtol, onIteration', () {
    double rosenbrock(List<double> p) =>
        (pow(1 - p[0], 2) + 100 * pow(p[1] - p[0] * p[0], 2)).toDouble();

    test('status of converged results', () async {
      double f(List<double> p) => pow(p[0] - 1, 2).toDouble() + 3;
      final r = await powell(f, [5]);
      expect(r.status, PowellStatus.absoluteToleranceReached);
      expect(r.converged, isTrue);

      final r2 = await powell(f, [5], aftol: 0);
      expect(r2.status, PowellStatus.relativeToleranceReached);
      expect(r2.converged, isTrue);
    });

    test('status maxIterationsReached', () async {
      final r = await powell(rosenbrock, [-1.2, 1], maxIterations: 2);
      expect(r.status, PowellStatus.maxIterationsReached);
      expect(r.converged, isFalse);
      expect(r.iterations, 2);
    });

    test('evaluations counts all calls of the objective', () async {
      int calls = 0;
      double f(List<double> p) {
        calls++;
        return rosenbrock(p);
      }

      final r = await powell(f, [-1.2, 1]);
      expect(r.evaluations, calls);
      expect(r.evaluations, greaterThan(r.iterations));
    });

    test('maxEvaluations stops with the best point seen', () async {
      int calls = 0;
      double f(List<double> p) {
        calls++;
        return rosenbrock(p);
      }

      final start = [-1.2, 1.0];
      final r = await powell(f, start, maxEvaluations: 50);
      expect(r.status, PowellStatus.maxEvaluationsReached);
      expect(r.converged, isFalse);
      // 50 during the search plus the final evaluation at the result
      expect(calls, 51);
      expect(r.evaluations, 51);
      expect(r.objective, equals(rosenbrock(r.value)));
      expect(r.objective, lessThan(rosenbrock(start)));
      expect(r.message, contains("50"));
    });

    test('maxEvaluations with an objective that is always NaN', () async {
      final r = await powell((p) => double.nan, [1.0, 2.0], maxEvaluations: 5);
      expect(r.status, PowellStatus.maxEvaluationsReached);
      expect(r.value, [1.0, 2.0]);
      expect(r.objective, isNaN);
    });

    test('maxEvaluations large enough does not interfere', () async {
      final r = await powell(rosenbrock, [-1.2, 1], maxEvaluations: 100000);
      expect(r.converged, isTrue);
      expect(r.value[0], closeTo(1, 1e-2));
      expect(r.value[1], closeTo(1, 1e-2));
    });

    test('xtol controls the precision of the line search', () async {
      double f(List<double> p) =>
          (pow(p[0] - 0.123456, 2) + pow(p[1] + 0.654321, 2)).toDouble();
      final fine = await powell(f, [0, 0], xtol: 1e-9, aftol: 1e-15);
      expect(fine.value[0], closeTo(0.123456, 1e-6));
      expect(fine.value[1], closeTo(-0.654321, 1e-6));
      final coarse = await powell(f, [0, 0], xtol: 1e-2, aftol: 1e-15);
      expect(coarse.evaluations, lessThan(fine.evaluations));
      expect((coarse.value[0] - 0.123456).abs(),
          greaterThan((fine.value[0] - 0.123456).abs()));
    });

    test('onIteration is called after each iteration', () async {
      final progress = <PowellProgress>[];
      final r = await powell(rosenbrock, [-1.2, 1], onIteration: (p) {
        progress.add(p);
        return true;
      });
      expect(r.converged, isTrue);
      // Called for every iteration except the converging one
      expect(progress.map((p) => p.iteration),
          List.generate(r.iterations - 1, (i) => i + 1));
      for (int i = 1; i < progress.length; i++) {
        expect(progress[i].evaluations,
            greaterThanOrEqualTo(progress[i - 1].evaluations));
        expect(progress[i].objective,
            lessThanOrEqualTo(progress[i - 1].objective));
      }
      expect(progress.last.objective, equals(rosenbrock(progress.last.value)));
      expect(() => progress.last.value[0] = 0, throwsUnsupportedError);
    });

    test('onIteration returning false stops', () async {
      final r = await powell(rosenbrock, [-1.2, 1],
          onIteration: (p) => p.iteration < 3);
      expect(r.status, PowellStatus.stoppedByCallback);
      expect(r.converged, isFalse);
      expect(r.iterations, 3);
      expect(r.objective, equals(rosenbrock(r.value)));
    });

    test('asynchronous onIteration (e.g. cancel flag)', () async {
      bool cancelled = false;
      final r = await powell(rosenbrock, [-1.2, 1], onIteration: (p) async {
        await Future.delayed(Duration.zero);
        if (p.iteration == 2) cancelled = true;
        return !cancelled;
      });
      expect(r.status, PowellStatus.stoppedByCallback);
      expect(r.iterations, 2);
    });
  });

  group('powell with bounds', () {
    // Rosenbrock function with its minimum at (1, 1)
    double rosenbrock(List<double> p) =>
        pow(1 - p[0], 2) + 100 * pow(p[1] - p[0] * p[0], 2).toDouble();

    // Wraps f, fails the test if it is evaluated outside the bounds
    double Function(List<double>) guarded(double Function(List<double>) f,
            List<double?> lower, List<double?> upper) =>
        (List<double> p) {
          for (int i = 0; i < p.length; i++) {
            if ((lower[i] != null && p[i] < lower[i]!) ||
                (upper[i] != null && p[i] > upper[i]!)) {
              fail("Evaluated outside the bounds at $p");
            }
          }
          return f(p);
        };

    test('minimum inside the bounds', () async {
      final lower = [-2.0, -2.0];
      final upper = [2.0, 2.0];
      final r = await powell(guarded(rosenbrock, lower, upper), [-1.2, 1.0],
          lowerBounds: lower, upperBounds: upper, rftol: 1e-12, aftol: 1e-14);
      expect(r.converged, isTrue);
      expect(r.value[0], closeTo(1, 1e-3));
      expect(r.value[1], closeTo(1, 1e-3));
    });

    test('minimum on a bound', () async {
      // Unconstrained minimum at (3, -2); bounded: (1, -2)
      double f(List<double> p) => pow(p[0] - 3, 2) + pow(p[1] + 2, 2) + 1.0;
      final lower = [null, -5.0];
      final upper = [1.0, null];
      final r = await powell(guarded(f, lower, upper), [0.0, 0.0],
          lowerBounds: lower, upperBounds: upper);
      expect(r.converged, isTrue);
      expect(r.value[0], 1.0);
      expect(r.value[1], closeTo(-2, 1e-3));
      expect(r.objective, closeTo(5, 1e-6));
    });

    test('minimum in a corner, coupled parameters', () async {
      // Unconstrained minimum at (1, 1)
      final lower = [-3.0, -3.0];
      final upper = [0.5, 0.5];
      final r = await powell(guarded(rosenbrock, lower, upper), [-1.0, 0.0],
          lowerBounds: lower, upperBounds: upper, rftol: 1e-12, aftol: 1e-14);
      expect(r.converged, isTrue);
      // Minimum of (1-x)^2 + 100 (0.25 - x^2)^2 for x <= 0.5 is at x = 0.5
      expect(r.value[0], closeTo(0.5, 1e-4));
      expect(r.value[1], closeTo(0.25, 1e-4));
    });

    test('function undefined outside the bounds', () async {
      // -log(x) + x has its minimum at x = 1; log is undefined for x <= 0
      double f(List<double> p) => -log(p[0]) + p[0] + pow(p[1] - 2, 2);
      final r = await powell(f, [0.01, 0.0],
          lowerBounds: [1e-12, null], initialScale: [10, 1]);
      expect(r.converged, isTrue);
      expect(r.value[0], closeTo(1, 1e-3));
      expect(r.value[1], closeTo(2, 1e-3));
    });

    test('start on a bound', () async {
      double f(List<double> p) => pow(p[0] - 0.5, 2) + pow(p[1] - 0.5, 2) + 0.0;
      final lower = [0.0, 0.0];
      final upper = [1.0, 1.0];
      final r = await powell(guarded(f, lower, upper), [0.0, 1.0],
          lowerBounds: lower, upperBounds: upper);
      expect(r.converged, isTrue);
      expect(r.value[0], closeTo(0.5, 1e-3));
      expect(r.value[1], closeTo(0.5, 1e-3));
    });

    test('equal bounds fix a parameter', () async {
      double f(List<double> p) => pow(p[0] - 3, 2) + pow(p[1] - 4, 2) + 0.0;
      final r = await powell(f, [0.0, 1.0],
          lowerBounds: [null, 1.0], upperBounds: [null, 1.0]);
      expect(r.converged, isTrue);
      expect(r.value[0], closeTo(3, 1e-3));
      expect(r.value[1], 1.0);
    });

    test('without bounds, null and infinite bounds give the same result',
        () async {
      final a = await powell(rosenbrock, [-1.2, 1.0]);
      final b = await powell(rosenbrock, [-1.2, 1.0],
          lowerBounds: [null, double.negativeInfinity],
          upperBounds: [double.infinity, null]);
      expect(b.value[0], closeTo(a.value[0], 1e-9));
      expect(b.value[1], closeTo(a.value[1], 1e-9));
      expect(b.converged, a.converged);
    });

    test('invalid bounds throw ArgumentError', () async {
      double f(List<double> p) => p[0] * p[0] + p[1] * p[1];
      // Start point outside
      await expectLater(
          powell(f, [2.0, 0.0], upperBounds: [1.0, null]), throwsArgumentError);
      await expectLater(powell(f, [0.0, -2.0], lowerBounds: [null, -1.0]),
          throwsArgumentError);
      await expectLater(powell(f, [double.nan, 0.0], lowerBounds: [0.0, null]),
          throwsArgumentError);
      // Wrong length
      await expectLater(
          powell(f, [0.0, 0.0], lowerBounds: [0.0]), throwsArgumentError);
      await expectLater(powell(f, [0.0, 0.0], upperBounds: [1.0, 1.0, 1.0]),
          throwsArgumentError);
      // NaN, lower > upper
      await expectLater(powell(f, [0.0, 0.0], lowerBounds: [double.nan, null]),
          throwsArgumentError);
      await expectLater(
          powell(f, [0.0, 0.0],
              lowerBounds: [1.0, null], upperBounds: [-1.0, null]),
          throwsArgumentError);
    });
  });
}
