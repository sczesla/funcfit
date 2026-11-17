import 'data.dart';
import 'likelihoods.dart';
import 'model.dart';

/// Noise model of a [CurveModel].
enum Noise {
  /// Normally distributed residuals ([gaussianLnL]).
  gaussian,

  /// Laplace-distributed residuals ([laplaceLnL]); robust against outliers.
  ///
  /// The objective has kinks (absolute values), so Powell's method may
  /// end slightly above the minimum; see "Non-smooth objectives" in the
  /// documentation of `powell()`.
  laplace,
}

/// A model computing a curve that is compared with [XYData] under a
/// selectable [noise] model.
///
/// Subclasses define the parameters and [evaluate]; the objective is the
/// negative log-likelihood for the chosen noise model:
///
/// ```dart
/// class Line extends CurveModel {
///   Line({super.noise}) : super(["a", "b"]);
///
///   @override
///   List<double> evaluate(List<double> x) {
///     final a = this["a"], b = this["b"];
///     return [for (final xi in x) a + b * xi];
///   }
/// }
///
/// final line = Line();
/// await fit(line, XYData(x, y, err: err));
/// ```
///
/// Models with additional noise parameters (e.g., a fitted jitter added to
/// the errors) can override [lnL] and pass them to [gaussianLnL] or
/// [laplaceLnL].
abstract class CurveModel extends Model<XYData> {
  /// [children] are the parameter sets of components, for composite models
  /// such as [CurveSum].
  ///
  /// Throws an [ArgumentError] for invalid names (see `ParameterSet`).
  CurveModel(super.names, {this.noise = Noise.gaussian, super.children});

  /// Noise model of the comparison with the data.
  final Noise noise;

  /// Model values for the independent variable [x], to be compared with
  /// the y values of the data (same length as y; [x] may differ in length,
  /// e.g., for interval boundaries).
  List<double> evaluate(List<double> x);

  /// Log-likelihood of [data] at the current parameter values.
  double lnL(XYData data) {
    final model = evaluate(data.x);
    return switch (noise) {
      Noise.gaussian => gaussianLnL(model, data.y, data.err),
      Noise.laplace => laplaceLnL(model, data.y, data.err),
    };
  }

  /// Negative log-likelihood of [data].
  @override
  double objective(XYData data) => -lnL(data);
}
