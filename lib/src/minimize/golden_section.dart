import 'dart:math';

double _invGoldenRatio = (sqrt(5.0) - 1) / 2.0;

/// Result of [goldenSection].
class GoldenSectionResult {
  /// Creates a result; [value] is null if the search failed.
  GoldenSectionResult(this.value,
      {this.message = "",
      this.intervalSearchIterations,
      this.sectionIterations,
      this.bestX,
      this.bestF});

  /// Location of the minimum or null if the search failed
  final double? value;

  /// Why the search failed; empty on success.
  final String message;

  /// Number of rounds needed to bracket the minimum (relocating or
  /// enlarging the interval).
  final int? intervalSearchIterations;

  /// Number of golden sections carried out; null if no minimum was
  /// bracketed.
  final int? sectionIterations;

  /// Point with the lowest function value evaluated during the search
  /// (also available if the search failed)
  final double? bestX;

  /// Function value at [bestX]
  final double? bestF;

  @override
  String toString() {
    return "GoldenSectionResult: value = $value, message = $message, "
        "intervalSearchIterations = $intervalSearchIterations, "
        "sectionIterations = $sectionIterations, bestX = $bestX, "
        "bestF = $bestF";
  }
}

/// Find minimum by golden section algorithm.
/// The starting interval is between [xlow] and [xup] if specified or
/// `xc - scale` and `xc + scale`. If the initial interval is found to be
/// unsuitable, an attempt is made to enlarge it. The maximum number
/// of attempts is given by [maxIntervalSearchIterations]. The maximum
/// of sections applied to find the minimum is given by [maxSectionIterations].
///
/// Optional hard bounds [lowerBound] and [upperBound] (null or infinite: no
/// bound) restrict the search: [f] is never evaluated outside
/// `[lowerBound, upperBound]`, and the search interval is clipped to it. If
/// the function decreases towards a bound, the minimum is searched between
/// [xc] and the bound; if the bound itself is the best point found, exactly
/// the bound is returned. Throws an [ArgumentError] if a bound is NaN, if
/// [lowerBound] > [upperBound], if [xc] is not within the bounds, or if
/// neither [xlow] (or [xup]) nor [scale] is given. If both
/// bounds are equal, [xc] is returned after a single evaluation.
///
/// ```dart
///       double f(double x) {
///         return x * x;
///       }
///
///       double tolerance = 1e-5;
///
///       GoldenSectionResult gsr = goldenSection(
///           f, 4, scale: 1, tolerance: tolerance);
/// ```
GoldenSectionResult goldenSection(double Function(double) f, double xc,
    {double? scale,
    double? xlow,
    double? xup,
    double? lowerBound,
    double? upperBound,
    double tolerance = 1e-4,
    int maxIntervalSearchIterations = 20,
    int maxSectionIterations = 500}) {
  int intervalIterations = 0;

  // Keep track of the best point seen, so that callers can make use of it
  // even if no minimum could be bracketed
  double bestX = xc;
  double bestF = double.infinity;
  double fEval(double x) {
    final double v = f(x);
    if (v < bestF) {
      bestF = v;
      bestX = x;
    }
    return v;
  }

  GoldenSectionResult failure(String message) => GoldenSectionResult(null,
      message: message,
      intervalSearchIterations: intervalIterations,
      bestX: bestF.isFinite ? bestX : null,
      bestF: bestF.isFinite ? bestF : null);

  final double lb = lowerBound ?? double.negativeInfinity;
  final double ub = upperBound ?? double.infinity;
  if (lb.isNaN || ub.isNaN) {
    throw ArgumentError("Bounds must not be NaN");
  }
  if (lb > ub) {
    throw ArgumentError("lowerBound ($lb) is greater than upperBound ($ub)");
  }
  if (!(xc >= lb && xc <= ub)) {
    throw ArgumentError.value(xc, "xc", "Must be within the bounds [$lb, $ub]");
  }
  if (lb == ub) {
    // Nothing to search
    fEval(xc);
    return GoldenSectionResult(xc,
        intervalSearchIterations: 0,
        sectionIterations: 0,
        bestX: bestF.isFinite ? bestX : null,
        bestF: bestF.isFinite ? bestF : null);
  }

  // Function value at xc, if already known (xc is always a point evaluated
  // before, except in the first round)
  double? fcKnown;

  while (true) {
    if (xlow == null) {
      if (scale == null) {
        throw ArgumentError("Either xlow or scale must be given");
      }
      xlow = xc - scale;
    }
    if (xup == null) {
      if (scale == null) {
        throw ArgumentError("Either xup or scale must be given");
      }
      xup = xc + scale;
    }
    // Never leave the bounds
    xlow = max(xlow, lb);
    xup = min(xup, ub);

    if ((xlow > xc) || (xup < xc)) {
      return failure("xlow<xc<xup must be satisfied.");
    }

    // Endpoints coinciding with xc (at a bound) are not evaluated again
    final double fc = fcKnown ?? fEval(xc);
    final double flow = xlow == xc ? fc : fEval(xlow);
    final double fup = xup == xc ? fc : fEval(xup);

    if ((fc < flow) && (fc < fup)) {
      // A minimum is in-between
      break;
    }
    // At a bound, the function only has to rise towards the other endpoint
    // (xlow or xup coincides with xc then)
    if ((xc == lb && fc < fup) || (xc == ub && fc < flow)) {
      break;
    }

    // Moving xc to an endpoint at a bound is always worthwhile: the next
    // round either brackets the minimum or turns around
    final bool betterAtBound = flow < fup ? xlow == lb : xup == ub;
    if (intervalIterations % 2 == 0 || betterAtBound) {
      // Relocate xc to the boundary point with the lower function value
      // (either flow or fup must be the smallest because fc isn't).
      // If the interval was given explicitly by xlow and xup, there is no
      // reason to preserve it; use its half-width as scale from now on.
      scale ??= (xup - xlow) / 2;
      if (flow < fup) {
        xc = xlow;
        fcKnown = flow;
      } else {
        xc = xup;
        fcKnown = fup;
      }
    } else {
      // Enlarge the interval around xc (fc stays valid)
      scale = 2 * max((xup - xc).abs(), (xlow - xc).abs());
      fcKnown = fc;
    }
    xup = null;
    xlow = null;
    intervalIterations++;
    if (intervalIterations == maxIntervalSearchIterations) {
      return failure(
          "maxIntervalSearchIterations reached. Problem with search interval (scale = $scale)");
    }
  }

  // Section phase: the interior points x1 < x2 divide [lo, hi] in the
  // golden ratio. After shrinking the interval, one of them is again at the
  // golden position of the new interval and keeps its function value, so
  // only one new evaluation is needed per section. New values are computed
  // only when needed (none after the last section).
  int sections = 0;
  double lo = xlow;
  double hi = xup;
  double x1 = hi - (hi - lo) * _invGoldenRatio;
  double x2 = lo + (hi - lo) * _invGoldenRatio;
  double? f1;
  double? f2;
  while (hi - lo > tolerance) {
    if (sections == maxSectionIterations) {
      return failure(
          "maxSectionIterations reached. You may try to decrease tolerance or adapt search interval.");
    }
    f1 ??= fEval(x1);
    f2 ??= fEval(x2);
    if (f1 < f2) {
      // Minimum in [lo, x2]; old x1 becomes the new x2
      hi = x2;
      x2 = x1;
      f2 = f1;
      x1 = hi - (hi - lo) * _invGoldenRatio;
      f1 = null;
    } else {
      // Minimum in [x1, hi]; old x2 becomes the new x1
      lo = x1;
      x1 = x2;
      f1 = f2;
      x2 = lo + (hi - lo) * _invGoldenRatio;
      f2 = null;
    }
    sections++;
  }
  xlow = lo;
  xup = hi;

  double value = (xup + xlow) / 2;
  if ((bestX == lb || bestX == ub) && bestX >= xlow && bestX <= xup) {
    // Minimum at a bound: return it exactly
    value = bestX;
  }

  return GoldenSectionResult(value,
      intervalSearchIterations: intervalIterations,
      sectionIterations: sections,
      bestX: bestX,
      bestF: bestF);
}
