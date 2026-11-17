// Fitting an additional noise term ("jitter").
//
// The data scatter more than their stated uncertainties err suggest. A
// jitter parameter, added in quadrature to err, estimates the unknown
// extra scatter together with the line. CurveModel provides the
// comparison with the data; the model overrides lnL to pass the jitter to
// gaussianLnL.
//
// Run with: dart run example/line_with_jitter.dart

import 'dart:math';

import 'package:funcfit/funcfit.dart';

/// Straight line y = a + b·x with an additional noise parameter "jitter".
class JitterLine extends CurveModel {
  JitterLine() : super(["a", "b", "jitter"]) {
    setLimits("jitter", 0, null);
  }

  @override
  List<double> evaluate(List<double> x) {
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }

  /// Gaussian log-likelihood with effective errors sqrt(err² + jitter²).
  @override
  double lnL(XYData data) =>
      gaussianLnL(evaluate(data.x), data.y, data.err, jitter: this["jitter"]);
}

Future<void> main() async {
  // Line y = 1 + 0.5 x with a true scatter of 0.5, but stated errors of
  // only 0.1
  final random = Random(2);
  double normal() =>
      sqrt(-2 * log(1 - random.nextDouble())) *
      cos(2 * pi * random.nextDouble());
  final x = [for (int i = 0; i < 100; i++) i / 10];
  final y = [for (final xi in x) 1 + 0.5 * xi + 0.5 * normal()];
  final data = XYData(x, y, err: List.filled(x.length, 0.1));

  final model = JitterLine();
  model["jitter"] = 0.1; // start value
  final result = await fit(model, data);
  print(result);

  // Expected: the actual scatter of the simulated data around the true
  // line, minus the stated errors (in quadrature)
  double sum = 0;
  for (int i = 0; i < x.length; i++) {
    final r = y[i] - (1 + 0.5 * x[i]);
    sum += r * r;
  }
  final scatter = sqrt(sum / x.length);
  print("jitter = ${model["jitter"]}, expected about "
      "${sqrt(scatter * scatter - 0.1 * 0.1)} (data scatter $scatter)");
}
