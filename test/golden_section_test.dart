import 'package:test/test.dart';
import 'package:funcfit/minimize.dart';
import 'dart:math';

void main() {
  group('golden section', () {
    test('parabola', () {
      double f(double x) {
        return x * x;
      }

      double tolerance = 1e-5;

      GoldenSectionResult gsr =
          goldenSection(f, 4, scale: 1, tolerance: tolerance);
      expect(gsr.value, isNotNull);
      expect(gsr.value!.abs(), lessThanOrEqualTo(tolerance));
      print(gsr);
    });

    test('sine', () {
      double f(double x) {
        return sin(x);
      }

      double tolerance = 1e-5;

      GoldenSectionResult gsr =
          goldenSection(f, -1.57, xlow: -12, xup: 12, tolerance: tolerance);
      expect(gsr.value, isNotNull);
      print(gsr);
    });

    test('linear', () {
      double f(double x) {
        return x;
      }

      double tolerance = 1e-5;

      GoldenSectionResult gsr =
          goldenSection(f, 1, xlow: -1, xup: 1, tolerance: tolerance);
      expect(gsr.value, isNull);
      print(gsr);
    });

    // No. 6: explicit bounds that do not contain the minimum
    test('explicit bounds not containing minimum', () {
      double f(double x) => (x - 5) * (x - 5);
      GoldenSectionResult gsr =
          goldenSection(f, 0, xlow: -1, xup: 1, tolerance: 1e-5);
      expect(gsr.value, isNotNull);
      expect(gsr.value!, closeTo(5, 1e-4));
    });

    test('scale not containing minimum', () {
      double f(double x) => (x + 7) * (x + 7);
      GoldenSectionResult gsr = goldenSection(f, 0, scale: 0.1);
      expect(gsr.value, isNotNull);
      expect(gsr.value!, closeTo(-7, 1e-3));
    });

    // Best point is reported also on failure
    test('best point on failure', () {
      double f(double x) => x;
      GoldenSectionResult gsr = goldenSection(f, 0, scale: 1);
      expect(gsr.value, isNull);
      expect(gsr.bestX, isNotNull);
      expect(gsr.bestX!, lessThan(-1));
      expect(gsr.bestF, equals(f(gsr.bestX!)));
    });

    test('flat function fails without improvement', () {
      double f(double x) => 3.0;
      GoldenSectionResult gsr = goldenSection(f, 0, scale: 1);
      expect(gsr.value, isNull);
      expect(gsr.bestF, equals(3.0));
    });
    // No redundant evaluations: 3 for the first bracketing round, 2 per
    // further round (the center is known), and one per section plus one for
    // the first section
    test('number of evaluations', () {
      for (final (xc, scale, tol) in [
        (0.0, 0.1, 1e-6), // minimum outside the initial interval
        (2.9, 0.5, 1e-4), // minimum inside
        (3.0, 1.0, 1e-8),
      ]) {
        int calls = 0;
        double f(double x) {
          calls++;
          return (x - 3) * (x - 3);
        }

        final g = goldenSection(f, xc, scale: scale, tolerance: tol);
        expect(g.value!, closeTo(3, tol), reason: "xc = $xc");
        final sections = g.sectionIterations!;
        final expected = 3 +
            2 * g.intervalSearchIterations! +
            (sections > 0 ? sections + 1 : 0);
        expect(calls, expected, reason: "xc = $xc");
      }
    });
  });

  group('golden section with bounds', () {
    // Wraps f, records the evaluated points
    (double Function(double), List<double>) recording(
        double Function(double) f) {
      final xs = <double>[];
      return (
        (double x) {
          xs.add(x);
          return f(x);
        },
        xs
      );
    }

    void expectWithin(List<double> xs, double lo, double hi) {
      for (final x in xs) {
        expect(x, inInclusiveRange(lo, hi), reason: "evaluated at $x");
      }
    }

    test('minimum inside the bounds: same as without bounds', () {
      double f(double x) => (x - 1) * (x - 1);
      final free = goldenSection(f, 0, scale: 0.1, tolerance: 1e-6);
      final (g, xs) = recording(f);
      final r = goldenSection(g, 0,
          scale: 0.1, lowerBound: -5, upperBound: 5, tolerance: 1e-6);
      expect(r.value, closeTo(1, 1e-6));
      expect(r.value, closeTo(free.value!, 1e-12));
      expectWithin(xs, -5, 5);
    });

    test('minimum beyond the upper bound: returns exactly the bound', () {
      final (g, xs) = recording((x) => (x - 10) * (x - 10));
      final r = goldenSection(g, 0, scale: 0.1, upperBound: 2);
      expect(r.value, 2.0);
      expect(r.bestX, 2.0);
      expectWithin(xs, double.negativeInfinity, 2);
    });

    test('minimum beyond the lower bound: returns exactly the bound', () {
      final (g, xs) = recording((x) => x);
      final r = goldenSection(g, 0, scale: 1, lowerBound: -3.5);
      expect(r.value, -3.5);
      expectWithin(xs, -3.5, double.infinity);
    });

    test('bound within the initial interval', () {
      final (g, xs) = recording((x) => exp(x));
      final r = goldenSection(g, 0.5, xlow: -10, xup: 10, lowerBound: 0);
      expect(r.value, 0.0);
      expectWithin(xs, 0, 10);
    });

    test('start at a bound, minimum inside', () {
      final (g, xs) = recording((x) => (x - 0.3) * (x - 0.3));
      final r = goldenSection(g, 0,
          scale: 0.1, lowerBound: 0, upperBound: 1, tolerance: 1e-6);
      expect(r.value, closeTo(0.3, 1e-6));
      expectWithin(xs, 0, 1);
    });

    test('start at a bound, minimum at that bound', () {
      final (g, xs) = recording((x) => x);
      final r = goldenSection(g, 0, scale: 0.1, lowerBound: 0, upperBound: 1);
      expect(r.value, 0.0);
      expectWithin(xs, 0, 1);
    });

    test('start at a bound, minimum at the other bound', () {
      final (g, xs) = recording((x) => -x);
      final r = goldenSection(g, 0, scale: 0.1, lowerBound: 0, upperBound: 1);
      expect(r.value, 1.0);
      expectWithin(xs, 0, 1);
    });

    test('equal bounds: one evaluation', () {
      final (g, xs) = recording((x) => x * x);
      final r = goldenSection(g, 2, scale: 1, lowerBound: 2, upperBound: 2);
      expect(r.value, 2.0);
      expect(xs, [2.0]);
    });

    test('infinite bounds behave like no bounds', () {
      double f(double x) => (x - 7) * (x - 7);
      final a = goldenSection(f, 0, scale: 0.1);
      final b = goldenSection(f, 0,
          scale: 0.1,
          lowerBound: double.negativeInfinity,
          upperBound: double.infinity);
      expect(b.value, a.value);
      expect(b.intervalSearchIterations, a.intervalSearchIterations);
      expect(b.sectionIterations, a.sectionIterations);
    });

    test('invalid bounds or start point throw', () {
      double f(double x) => x;
      expect(() => goldenSection(f, 0, scale: 1, lowerBound: 1, upperBound: 0),
          throwsArgumentError);
      expect(() => goldenSection(f, 0, scale: 1, lowerBound: double.nan),
          throwsArgumentError);
      expect(() => goldenSection(f, 0, scale: 1, upperBound: double.nan),
          throwsArgumentError);
      expect(() => goldenSection(f, 2, scale: 1, upperBound: 1),
          throwsArgumentError);
      expect(() => goldenSection(f, -2, scale: 1, lowerBound: -1),
          throwsArgumentError);
    });
  });
}
