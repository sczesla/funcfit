// Fitting a straight line y = a + b*x with CurveModel and fit().
//
// Run with: dart run example/funcfit_example.dart

import 'package:funcfit/funcfit.dart';

/// Straight line `y = a + b * x`.
///
/// Pattern for building a curve model: extend [CurveModel], name the
/// parameters, and compute the curve in [evaluate]. The objective (negative
/// log-likelihood for the chosen noise model) is provided by [CurveModel].
class Line extends CurveModel {
  Line({super.noise}) : super(["a", "b"]);

  @override
  List<double> evaluate(List<double> x) {
    // Read parameter values once, not in the loop
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }
}

Future<void> main() async {
  final data = XYData([1, 2, 3, 4, 5, 6], [0.1, 1.9, 3.5, 4.1, 4.4, 6.1]);

  // Fit offset a and slope b (Gaussian noise: least squares)
  final line = Line();
  print(await fit(line, data));

  // Line through the origin: freeze a at 0 and fit b only
  line["a"] = 0;
  line.freeze("a");
  print(await fit(line, data));

  // Robust fit with Laplace noise (least absolute deviations)
  final robust = Line(noise: Noise.laplace);
  print(await fit(robust, data));
}
