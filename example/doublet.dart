// Combining models and tying parameters.
//
// A spectral doublet: two Gaussian lines on a sloped continuum. The
// separation of the two lines is known (2.0), and both have the same
// width. CurveSum adds the three components; relations make the second
// line's position and width depend on the first line's parameters, so the
// fit has two parameters fewer.
//
// Run with: dart run example/doublet.dart

import 'dart:math';

import 'package:funcfit/funcfit.dart';

/// Straight line y = a + b·x.
class Line extends CurveModel {
  Line() : super(["a", "b"]);

  @override
  List<double> evaluate(List<double> x) {
    final a = this["a"], b = this["b"];
    return [for (final xi in x) a + b * xi];
  }
}

/// Gaussian peak with amplitude "amp", position "mu", and width "sigma".
class Gaussian extends CurveModel {
  Gaussian() : super(["amp", "mu", "sigma"]);

  @override
  List<double> evaluate(List<double> x) {
    final amp = this["amp"], mu = this["mu"], sigma = this["sigma"];
    return [
      for (final xi in x)
        amp * exp(-(xi - mu) * (xi - mu) / (2 * sigma * sigma))
    ];
  }
}

Future<void> main() async {
  // Synthetic spectrum: continuum 1 + 0.05 x, lines at 4.0 and 6.0 with
  // amplitudes 3 and 1.5 and width 0.3, noise 0.05
  final random = Random(3);
  final x = [for (int i = 0; i <= 200; i++) i / 20];
  final y = [
    for (final xi in x)
      1 +
          0.05 * xi +
          3 * exp(-(xi - 4) * (xi - 4) / (2 * 0.09)) +
          1.5 * exp(-(xi - 6) * (xi - 6) / (2 * 0.09)) +
          0.05 * (2 * random.nextDouble() - 1)
  ];
  final data = XYData(x, y, err: List.filled(x.length, 0.05));

  // The components keep their own parameter names; in the sum they are
  // addressed as "label.name"
  final continuum = Line();
  final line1 = Gaussian();
  final line2 = Gaussian();
  final model =
      CurveSum({"continuum": continuum, "line1": line1, "line2": line2});

  // Start values
  model.params.setValues({
    "continuum.a": 1,
    "line1.amp": 2,
    "line1.mu": 3.8,
    "line1.sigma": 0.5,
    "line2.amp": 1,
  });

  // Known separation and equal widths: line2 follows line1
  model.relate("line2.mu", ["line1.mu"], (v) => v[0] + 2.0,
      description: "line1.mu + 2.0");
  model.relate("line2.sigma", ["line1.sigma"], (v) => v[0],
      description: "line1.sigma");

  final result = await fit(model, data);
  print(result.message);
  print(model.params); // dependent parameters show their relation
  // The components hold their part of the best fit
  print("line2 at ${line2["mu"]} with width ${line2["sigma"]}");
}
