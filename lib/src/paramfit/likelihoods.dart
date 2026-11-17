import 'dart:math';

final double _ln2pi = log(2 * pi);
final double _ln2 = log(2);

void _check(List<double> model, List<double> y, List<double>? err,
    double jitter, String fn) {
  if (model.length != y.length || (err != null && err.length != y.length)) {
    throw ArgumentError("$fn: model, y, and err must have the same length "
        "(got ${model.length}, ${y.length}, ${err?.length})");
  }
  if (!(jitter >= 0 && jitter.isFinite)) {
    throw ArgumentError.value(jitter, "jitter", "$fn: must be finite and >= 0");
  }
}

/// Log-likelihood of [y] for independent, normally distributed residuals
/// with standard deviations `s_i = sqrt(err_i^2 + jitter^2)` around [model]:
///
///     lnL = sum_i [ -ln(2 pi)/2 - ln(s_i) - (model_i - y_i)^2 / (2 s_i^2) ]
///
/// Points with infinite err carry no information and are skipped. [err]
/// must contain values > 0 (see [XYData]); if it is null, unit variance is
/// assumed (err_i = 1). [jitter] is an additional, e.g. fitted, noise term.
///
/// Throws an [ArgumentError] if the lengths differ or [jitter] is negative
/// or not finite.
double gaussianLnL(List<double> model, List<double> y, List<double>? err,
    {double jitter = 0}) {
  _check(model, y, err, jitter, "gaussianLnL");
  double r = 0;
  for (int i = 0; i < y.length; i++) {
    final e = err?[i] ?? 1.0;
    if (e == double.infinity) continue;
    final s = jitter == 0 ? e : sqrt(e * e + jitter * jitter);
    final d = model[i] - y[i];
    r -= 0.5 * _ln2pi + log(s) + d * d / (2 * s * s);
  }
  return r;
}

/// Log-likelihood of [y] for independent, Laplace-distributed residuals
/// (least absolute deviations; robust against outliers) with scale
/// parameters `b_i = sqrt(err_i^2 + jitter^2)` around [model]:
///
///     lnL = sum_i [ -ln(2 b_i) - |model_i - y_i| / b_i ]
///
/// The standard deviation of a Laplace distribution is `sqrt(2) * b`.
/// Combining [err] and [jitter] in quadrature is a convention for the
/// Laplace case. Points with infinite err are skipped. [err] must contain
/// values > 0 (see [XYData]); if it is null, unit variance is assumed
/// (err_i = b_i = 1/sqrt(2)).
///
/// As a function of the model values, it has kinks (absolute values);
/// derivative-free minimizers such as Powell's method may end slightly
/// above the optimum (see "Non-smooth objectives" at `powell()`).
///
/// Throws an [ArgumentError] if the lengths differ or [jitter] is negative
/// or not finite.
double laplaceLnL(List<double> model, List<double> y, List<double>? err,
    {double jitter = 0}) {
  _check(model, y, err, jitter, "laplaceLnL");
  double r = 0;
  for (int i = 0; i < y.length; i++) {
    final e = err?[i] ?? sqrt1_2;
    if (e == double.infinity) continue;
    final b = jitter == 0 ? e : sqrt(e * e + jitter * jitter);
    r -= _ln2 + log(b) + (model[i] - y[i]).abs() / b;
  }
  return r;
}
