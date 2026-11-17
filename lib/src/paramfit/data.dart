/// Data for a [CurveModel]-like comparison: values [y] with uncertainties
/// [err], and the independent variable [x].
///
/// [err] holds the uncertainties of the [y] values (for Gaussian noise the
/// standard deviations, for Laplace noise the scale parameters b). It must
/// have the same length as [y] and contain values > 0; infinity is allowed
/// and means that the point carries no information. If no uncertainties are
/// given, [err] is null, and the log-likelihoods assume unit variance (see
/// [gaussianLnL] and [laplaceLnL]). [x] may differ in length from [y] (e.g.,
/// interval boundaries for values averaged over intervals).
///
/// The constructor stores unmodifiable copies; later changes to the lists
/// passed in do not affect the data, and attempts to modify [x], [y], or
/// [err] throw an [UnsupportedError].
class XYData {
  /// Throws an [ArgumentError] if [err] does not match [y] in length or
  /// contains values that are not > 0 (including NaN).
  XYData(List<double> x, List<double> y, {List<double>? err})
      : x = List.unmodifiable(x),
        y = List.unmodifiable(y),
        err = _checkedErr(err, y.length);

  /// Independent variable.
  final List<double> x;

  /// Measured values.
  final List<double> y;

  /// Uncertainties of [y], or null if none were given (unit variance).
  final List<double>? err;

  static List<double>? _checkedErr(List<double>? err, int n) {
    if (err == null) return null;
    // Copy first, so that the check applies to the stored data
    err = List<double>.unmodifiable(err);
    if (err.length != n) {
      throw ArgumentError(
          "XYData: err has ${err.length} elements, but y has $n");
    }
    for (int i = 0; i < n; i++) {
      if (!(err[i] > 0)) {
        throw ArgumentError.value(
            err[i], "err[$i]", "XYData: must be > 0 (or infinity)");
      }
    }
    return err;
  }

  @override
  String toString() => "XYData: x = $x, y = $y, err = $err";
}
