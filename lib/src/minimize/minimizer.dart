/// An algorithm minimizing a function of several variables.
///
/// Further algorithms implement this interface; `fit()` of the parameter
/// layer (`paramfit.dart`) accepts any of them.
///
/// Implementations that do not support bounds must throw an [ArgumentError]
/// if bounds are given; bounds must never be silently ignored.
abstract interface class Minimizer {
  /// Minimizes [f] starting at [x0].
  ///
  /// [lower] and [upper] are optional bounds per variable (null list or
  /// element: no bound); [x0] lies within them.
  Future<MinimizerResult> minimize(
      double Function(List<double>) f, List<double> x0,
      {List<double?>? lower, List<double?>? upper});
}

/// What every [Minimizer] reports.
abstract interface class MinimizerResult {
  /// Best point found.
  List<double> get value;

  /// Value of the function at [value].
  double get objective;

  /// Whether a convergence criterion was met.
  bool get converged;

  /// Human-readable description of the outcome.
  String get message;

  /// Number of evaluations of the function.
  int get evaluations;
}
