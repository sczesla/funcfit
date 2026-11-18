import 'dart:async';
import 'dart:math';

import 'golden_section.dart';
import 'minimizer.dart';
import 'vector.dart';

/// Why [powell] stopped.
enum PowellStatus {
  /// The decrease of the objective in one iteration was below `aftol`.
  absoluteToleranceReached(converged: true),

  /// The relative decrease of the objective in one iteration was below
  /// `rftol`.
  relativeToleranceReached(converged: true),

  /// `maxIterations` iterations were carried out without convergence.
  maxIterationsReached(converged: false),

  /// `maxEvaluations` evaluations of the objective were carried out without
  /// convergence.
  maxEvaluationsReached(converged: false),

  /// The `onIteration` callback returned false.
  stoppedByCallback(converged: false);

  const PowellStatus({required this.converged});

  /// Whether this status means that a convergence criterion was met.
  final bool converged;
}

/// Result of [powell].
class PowellResult implements MinimizerResult {
  /// Creates a result; normally done by [powell].
  PowellResult(this.value, this.objective,
      {required this.status,
      required this.message,
      required this.iterations,
      required this.evaluations});

  /// Best-fit parameter values (the best point found, also if not converged).
  @override
  final List<double> value;

  /// Value of the objective at [value].
  @override
  final double objective;

  /// Why the optimization stopped.
  final PowellStatus status;

  /// True if a convergence criterion was met (see [status]).
  @override
  bool get converged => status.converged;

  /// Human-readable description of [status].
  @override
  final String message;

  /// Number of iterations (sweeps over all directions) started.
  final int iterations;

  /// Number of evaluations of the objective, including the final evaluation
  /// at the returned point.
  @override
  final int evaluations;

  @override
  String toString() {
    return "PowellResult: $message, status = ${status.name}, "
        "objective = $objective, values = $value, "
        "iterations = $iterations, evaluations = $evaluations";
  }
}

/// State after an iteration of [powell], passed to its `onIteration`
/// callback.
class PowellProgress {
  /// Creates a progress report; normally done by [powell].
  PowellProgress(this.iteration, this.evaluations, this.value, this.objective);

  /// Number of the iteration just completed (starting at 1).
  final int iteration;

  /// Number of evaluations of the objective so far.
  final int evaluations;

  /// Current point (read-only).
  final List<double> value;

  /// Value of the objective at [value].
  final double objective;

  @override
  String toString() => "PowellProgress: iteration = $iteration, "
      "evaluations = $evaluations, objective = $objective, values = $value";
}

/// Thrown by the counting wrapper of the objective when the evaluation
/// limit is reached; caught in [powell].
class _EvaluationLimitReached implements Exception {
  const _EvaluationLimitReached();
}

/// Minimize [objective] by Powell's method, starting at [pInitial].
///
/// [objective] receives the parameter values as a read-only list; trying to
/// modify it throws an [UnsupportedError]. Use `List.of(values)` to get a
/// modifiable copy.
///
/// [initialScale] gives the length of the initial (coordinate) search
/// directions; defaults to 1 for all parameters.
///
/// [xtol] is the tolerance of each line minimization, i.e., the precision of
/// the step length along a search direction, in units of that direction's
/// length (for the initial directions: [initialScale]).
///
/// Convergence is reached if the decrease of the objective during one
/// iteration is below [aftol] (absolute) or below
/// `rftol * (|f_start| + |f_end|) / 2` (relative), and no line search failed
/// to bracket a minimum while still finding a significantly lower value.
///
/// [lowerBounds] and [upperBounds] optionally restrict each parameter to a
/// range; a null list or element, or an infinite value, means no bound. The
/// objective is never evaluated outside the bounds: each line search is
/// restricted to the part of the search direction within the bounds, and the
/// extrapolated point used to decide on replacing a direction is shortened
/// to stay within them. Throws an [ArgumentError] if the lengths do not
/// match [pInitial], if a bound is NaN, if a lower bound exceeds the upper
/// one, if [pInitial] is not within the bounds, or if [objective] returns
/// NaN at [pInitial] (e.g., a division by a parameter starting at 0); the
/// objective may be infinite there. Equal bounds fix a
/// parameter. If the search converges at a bound after search directions
/// were replaced, the directions are reset to the initial coordinate
/// directions and convergence is only accepted with those, because the
/// replaced directions may all be blocked by the bound. Before convergence
/// on a bound is accepted, the parameters on the bound are moved inward by
/// a small step (`xtol` times their [initialScale]) and one more sweep of
/// line searches follows, the other parameters first. This finds better
/// points where a parameter on its bound removes the influence of others
/// (e.g., an amplitude at 0 makes phase and period irrelevant). Only a
/// significantly better point is taken; otherwise the result stays
/// exactly on the bound. No local method can rule out other non-optimal
/// end points, so a check with other start values remains useful; see
/// also the section "Bounds: use them sparingly" in the package README.
///
/// The search stops without convergence after [maxIterations] iterations,
/// after [maxEvaluations] evaluations of the objective (default: no limit),
/// or if [onIteration] returns false. [onIteration] is called after each
/// iteration that did not converge; it may be asynchronous, e.g., to check
/// whether the user cancelled the computation.
///
/// The result always holds the best point found; check
/// [PowellResult.status] or [PowellResult.converged]. Before returning,
/// [objective] is evaluated at the returned point once more (also when
/// [maxEvaluations] was reached), so objectives storing state (e.g., the
/// current parameter values) reflect the result.
///
/// **Non-smooth objectives:** Powell's method needs no derivatives but
/// assumes a smooth objective. At kinks (e.g., absolute values as in a
/// Laplace likelihood, clipping, or piecewise defined models), the line
/// searches can stall: convergence is reported while the objective is
/// still somewhat above its minimum, and tighter tolerances do not
/// necessarily help. The result is then close to, but not exactly at, the
/// optimum. To check, fit again from the result or from other start
/// values and compare the objectives; if precision matters, use a smooth
/// approximation of the objective (e.g., pseudo-Huber instead of absolute
/// values).
Future<PowellResult> powell(
    double Function(List<double>) objective, List<double> pInitial,
    {int maxIterations = 100,
    int? maxEvaluations,
    double rftol = 1e-6,
    double aftol = 1e-6,
    double xtol = 1e-4,
    List<double>? initialScale,
    List<double?>? lowerBounds,
    List<double?>? upperBounds,
    FutureOr<bool> Function(PowellProgress progress)? onIteration}) async {
  final int pn = pInitial.length;
  if (pn < 1) {
    throw ArgumentError.value(
        pInitial, "pInitial", "Must have at least one element");
  }
  if (maxEvaluations != null && maxEvaluations < 1) {
    throw ArgumentError.value(maxEvaluations, "maxEvaluations", "Must be >= 1");
  }
  if (!(xtol > 0 && xtol.isFinite)) {
    throw ArgumentError.value(xtol, "xtol", "Must be positive and finite");
  }
  if (initialScale != null) {
    if (initialScale.length != pn) {
      throw ArgumentError("initialScale has ${initialScale.length} elements, "
          "but pInitial has $pn");
    }
    if (initialScale.any((s) => s == 0 || !s.isFinite)) {
      throw ArgumentError.value(initialScale, "initialScale",
          "All elements must be finite and non-zero");
    }
  }

  // Bounds (infinite where there is none)
  final bool bounded = lowerBounds != null || upperBounds != null;
  for (final (name, b) in [
    ("lowerBounds", lowerBounds),
    ("upperBounds", upperBounds)
  ]) {
    if (b == null) continue;
    if (b.length != pn) {
      throw ArgumentError("$name has ${b.length} elements, "
          "but pInitial has $pn");
    }
    if (b.any((v) => v != null && v.isNaN)) {
      throw ArgumentError.value(b, name, "Must not contain NaN");
    }
  }
  final List<double> lb = [
    for (int i = 0; i < pn; i++) lowerBounds?[i] ?? double.negativeInfinity
  ];
  final List<double> ub = [
    for (int i = 0; i < pn; i++) upperBounds?[i] ?? double.infinity
  ];
  for (int i = 0; i < pn; i++) {
    if (lb[i] > ub[i]) {
      throw ArgumentError("Lower bound (${lb[i]}) of parameter $i is greater "
          "than its upper bound (${ub[i]})");
    }
    if (bounded && !(pInitial[i] >= lb[i] && pInitial[i] <= ub[i])) {
      throw ArgumentError.value(pInitial, "pInitial",
          "Element $i (${pInitial[i]}) is not within [${lb[i]}, ${ub[i]}]");
    }
  }

  /// Moves [x] into the bounds (in place); only guards against rounding.
  Vector clamp(Vector x) {
    if (bounded) {
      for (int i = 0; i < pn; i++) {
        x[i] = min(max(x[i], lb[i]), ub[i]);
      }
    }
    return x;
  }

  /// Range of step lengths alpha for which p + alpha * d is within the
  /// bounds; contains 0 because p is within the bounds.
  ({double min, double max}) stepRange(Vector p, Vector d) {
    double aMin = double.negativeInfinity;
    double aMax = double.infinity;
    for (int i = 0; i < pn; i++) {
      final di = d[i];
      if (di == 0) continue;
      final t1 = (lb[i] - p[i]) / di;
      final t2 = (ub[i] - p[i]) / di;
      if (di > 0) {
        aMin = max(aMin, t1);
        aMax = min(aMax, t2);
      } else {
        aMin = max(aMin, t2);
        aMax = min(aMax, t1);
      }
    }
    return (min: aMin, max: aMax);
  }

  // Counting wrapper of the objective; keeps track of the best point seen,
  // which is returned if the evaluation limit is reached
  int evaluations = 0;
  bool limitActive = true;
  double bestF = double.infinity;
  List<double>? bestX;
  double f(List<double> x) {
    if (limitActive &&
        maxEvaluations != null &&
        evaluations >= maxEvaluations) {
      throw const _EvaluationLimitReached();
    }
    evaluations++;
    final v = objective(x);
    if (v < bestF) {
      bestF = v;
      bestX = List.of(x);
    }
    return v;
  }

  // Initial directions
  List<Vector> initialDirections() => [
        for (int i = 0; i < pn; i++)
          Vector.zeros(pn)..[i] = initialScale?[i] ?? 1.0
      ];
  List<Vector> xis = initialDirections();
  // Whether a direction was replaced since the last (re)set
  bool directionsModified = false;

  bool atBound(Vector p) {
    for (int i = 0; i < pn; i++) {
      if (p[i] == lb[i] || p[i] == ub[i]) return true;
    }
    return false;
  }

  bool isAbsConverged(double fa, double fb) => (fa - fb).abs() < aftol;
  // Robust against fa, fb = 0 (cf. Numerical Recipes)
  bool isRelConverged(double fa, double fb) =>
      2 * (fa - fb).abs() <= rftol * (fa.abs() + fb.abs()) + 1e-20;
  bool isSmallChange(double fa, double fb) =>
      isAbsConverged(fa, fb) || isRelConverged(fa, fb);

  /// Minimize along [direction] starting from [p] (with value [fp]).
  /// Never returns a point worse than [p]. [failed] is true if no minimum
  /// could be bracketed although a significantly lower value was found
  /// (the minimum is out of reach or the objective is unbounded).
  ({Vector p, double f, bool failed}) lineMinimize(
      Vector p, double fp, Vector direction, double scale) {
    Vector at(double alpha) => clamp(p + direction * alpha);
    double fx(double alpha) => f(at(alpha).data);

    double? aMin;
    double? aMax;
    if (bounded) {
      final range = stepRange(p, direction);
      if (range.min == range.max) {
        // No room to move along this direction
        return (p: p, f: fp, failed: false);
      }
      aMin = range.min;
      aMax = range.max;
    }

    GoldenSectionResult gsr = goldenSection(fx, 0.0,
        scale: scale, tolerance: xtol, lowerBound: aMin, upperBound: aMax);
    double step = gsr.value ?? 0.0;
    bool failed = false;
    if (gsr.value == null) {
      // E.g. flat direction (fine, stay) or minimum not bracketed (take
      // the best point seen and keep iterating)
      if (gsr.bestF != null && gsr.bestF! < fp) {
        step = gsr.bestX!;
        failed = !isSmallChange(fp, gsr.bestF!);
      }
    }
    if (step == 0.0) {
      return (p: p, f: fp, failed: failed);
    }
    Vector pNew = at(step);
    double fNew = f(pNew.data);
    if (!(fNew <= fp)) {
      // Never accept a worse point (or NaN)
      return (p: p, f: fp, failed: failed);
    }
    return (p: pNew, f: fNew, failed: failed);
  }

  /// Checks a point [p] converged on a bound for a better point nearby.
  ///
  /// At a bound, the remaining parameters can lose all influence (e.g., an
  /// amplitude at 0 makes phase and period irrelevant): no single direction
  /// decreases the objective, although a combined move would. The
  /// parameters on a bound are moved inward by a small step, and one sweep
  /// of line searches follows, first along the other parameters, then along
  /// those moved. Returns the new point if it is significantly better than
  /// [fp], otherwise null (and [p] is kept exactly on the bound).
  ({Vector p, double f})? probeBound(Vector p, double fp) {
    final q = Vector.fromList(p.toList());
    final onBound = <int>[];
    for (int i = 0; i < pn; i++) {
      if (lb[i] == ub[i] || (p[i] != lb[i] && p[i] != ub[i])) continue;
      final step =
          min(xtol * (initialScale?[i] ?? 1.0).abs(), (ub[i] - lb[i]) / 2);
      q[i] = p[i] == lb[i] ? lb[i] + step : ub[i] - step;
      onBound.add(i);
    }
    if (onBound.isEmpty) return null;
    final dirs = initialDirections();
    Vector pq = q;
    double fq = f(q.data);
    for (final i in [
      for (int i = 0; i < pn; i++)
        if (!onBound.contains(i)) i,
      ...onBound
    ]) {
      final r = lineMinimize(pq, fq, dirs[i], 0.1);
      pq = r.p;
      fq = r.f;
    }
    if (fq < fp && !isSmallChange(fp, fq)) return (p: pq, f: fq);
    return null;
  }

  String messageFor(PowellStatus status, int it) => switch (status) {
        PowellStatus.absoluteToleranceReached =>
          "Absolute convergence criterion reached after $it iterations",
        PowellStatus.relativeToleranceReached =>
          "Relative convergence criterion reached after $it iterations",
        PowellStatus.maxIterationsReached =>
          "Maximum number of iterations ($maxIterations) reached",
        PowellStatus.maxEvaluationsReached =>
          "Maximum number of evaluations ($maxEvaluations) reached "
              "after $it iterations",
        PowellStatus.stoppedByCallback =>
          "Stopped by callback after $it iterations",
      };

  PowellResult result(Vector p, double fp, PowellStatus status, int it) {
    // Leave stateful objectives at the returned point (the evaluation
    // limit no longer applies)
    limitActive = false;
    f(p.data);
    return PowellResult(p.toList(), fp,
        status: status,
        message: messageFor(status, it),
        iterations: it,
        evaluations: evaluations);
  }

  int iterations = 0;
  try {
    Vector p0 = Vector.fromList(pInitial);
    double f0 = f(p0.data);
    if (f0.isNaN) {
      throw ArgumentError("The objective is NaN at the starting point "
          "$pInitial; choose start values for which it is defined");
    }

    for (iterations = 1; iterations <= maxIterations; iterations++) {
      // The sole purpose of this is to give the UI some time to update
      // to e.g. display rotating overlays
      await Future.delayed(Duration.zero);

      // Points and objective values after each line minimization
      List<Vector> pr = [p0];
      List<double> fi = [f0];
      bool lineSearchFailed = false;
      for (int i = 0; i < pn; i++) {
        final r = lineMinimize(pr.last, fi.last, xis[i], 0.1);
        pr.add(r.p);
        fi.add(r.f);
        lineSearchFailed |= r.failed;
      }

      if (!lineSearchFailed &&
          isSmallChange(fi.first, fi.last) &&
          directionsModified &&
          atBound(pr.last)) {
        // The modified directions may all be blocked by the bound although
        // the coordinate directions still allow progress along it; only
        // accept convergence with the coordinate directions
        xis = initialDirections();
        directionsModified = false;
        p0 = pr.last;
        f0 = fi.last;
        if (onIteration != null &&
            !await onIteration(
                PowellProgress(iterations, evaluations, p0.data, f0))) {
          return result(p0, f0, PowellStatus.stoppedByCallback, iterations);
        }
        continue;
      }

      if (!lineSearchFailed) {
        final status = isAbsConverged(fi.first, fi.last)
            ? PowellStatus.absoluteToleranceReached
            : isRelConverged(fi.first, fi.last)
                ? PowellStatus.relativeToleranceReached
                : null;
        if (status != null) {
          final probe =
              bounded && atBound(pr.last) ? probeBound(pr.last, fi.last) : null;
          if (probe == null) {
            return result(pr.last, fi.last, status, iterations);
          }
          // A better point next to the bound: continue from there
          xis = initialDirections();
          directionsModified = false;
          p0 = probe.p;
          f0 = probe.f;
          if (onIteration != null &&
              !await onIteration(
                  PowellProgress(iterations, evaluations, p0.data, f0))) {
            return result(p0, f0, PowellStatus.stoppedByCallback, iterations);
          }
          continue;
        }
      }

      // Direction with the largest decrease; none (-1) if no line search
      // decreased the objective comparably (e.g., all values infinite)
      double delta = -double.infinity;
      int mMaxDecrease = -1;
      for (int m = 0; m < pn; m++) {
        double d = fi[m] - fi[m + 1];
        if (d > delta) {
          mMaxDecrease = m;
          delta = d;
        }
      }

      double f1 = fi.first;
      double f2 = fi.last;
      double f3;
      if (!bounded) {
        f3 = f((pr.last * 2 - pr.first).data);
      } else {
        // Extrapolate only as far as the bounds allow (as scipy does)
        final dir = pr.last - pr.first;
        final t = min(1.0, stepRange(pr.last, dir).max);
        f3 = t > 0 ? f(clamp(pr.last + dir * t).data) : f2;
      }

      if (mMaxDecrease < 0 ||
          (f3 >= f1) ||
          ((f1 - 2 * f2 + f3) * pow(f1 - f2 - delta, 2) >=
              0.5 * delta * pow(f1 - f3, 2))) {
        // Keep the old directions; continue from the last point
        p0 = pr.last;
        f0 = fi.last;
      } else {
        // Replace the direction of largest decrease by the average direction
        // of this iteration and minimize along it
        Vector xiNew = pr.last - pr.first;
        final r = lineMinimize(pr.last, fi.last, xiNew, 1.0);
        xis.removeAt(mMaxDecrease);
        xis.add(xiNew);
        directionsModified = true;
        p0 = r.p;
        f0 = r.f;
      }

      if (onIteration != null &&
          !await onIteration(
              PowellProgress(iterations, evaluations, p0.data, f0))) {
        return result(p0, f0, PowellStatus.stoppedByCallback, iterations);
      }
    }

    return result(p0, f0, PowellStatus.maxIterationsReached, maxIterations);
  } on _EvaluationLimitReached {
    // bestX is null only if the objective never returned a number < inf;
    // then the start is returned (its value is infinite, never NaN)
    final x = bestX;
    return result(x == null ? Vector.fromList(pInitial) : Vector.fromList(x),
        bestF, PowellStatus.maxEvaluationsReached, iterations);
  }
}

/// Powell's method as a [Minimizer]; holds the options of [powell].
///
/// When used with `fit()` of the parameter layer, [initialScale] refers to
/// the free parameters in the order of `ParameterSet.freeNames()`.
class Powell implements Minimizer {
  /// Creates the minimizer; the options are those of [powell].
  const Powell(
      {this.maxIterations = 100,
      this.maxEvaluations,
      this.rftol = 1e-6,
      this.aftol = 1e-6,
      this.xtol = 1e-4,
      this.initialScale,
      this.onIteration});

  /// See [powell].
  final int maxIterations;

  /// See [powell].
  final int? maxEvaluations;

  /// See [powell].
  final double rftol;

  /// See [powell].
  final double aftol;

  /// See [powell].
  final double xtol;

  /// See [powell].
  final List<double>? initialScale;

  /// See [powell].
  final FutureOr<bool> Function(PowellProgress progress)? onIteration;

  @override
  Future<PowellResult> minimize(
          double Function(List<double>) f, List<double> x0,
          {List<double?>? lower, List<double?>? upper}) =>
      powell(f, x0,
          maxIterations: maxIterations,
          maxEvaluations: maxEvaluations,
          rftol: rftol,
          aftol: aftol,
          xtol: xtol,
          initialScale: initialScale,
          lowerBounds: lower,
          upperBounds: upper,
          onIteration: onIteration);
}
