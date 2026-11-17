// Fitting step by step, and trying several start values.
//
// Nonlinear fits can get stuck: a narrow peak far from its true position
// has almost no influence on the objective, so the fit cannot find its way.
// Two common remedies:
// 1. Fit step by step: first only the "easy" parameters with the others
//    frozen, then everything.
// 2. Start from several values and keep the best result.
//
// Run with: dart run example/stepwise_and_starts.dart

import 'dart:math';

import 'package:funcfit/funcfit.dart';

/// Gaussian peak on a constant background.
class Peak extends CurveModel {
  Peak() : super(["background", "amp", "mu", "sigma"]);

  @override
  List<double> evaluate(List<double> x) {
    final c = this["background"], amp = this["amp"];
    final mu = this["mu"], sigma = this["sigma"];
    return [
      for (final xi in x)
        c + amp * exp(-(xi - mu) * (xi - mu) / (2 * sigma * sigma))
    ];
  }
}

/// Fits [model] to [data] in two steps, starting with the peak at [mu0].
Future<FitResult> fitFrom(Peak model, XYData data, double mu0) async {
  model.params.setValues({"background": 0, "amp": 1, "mu": mu0, "sigma": 0.5});

  // Step 1: position and width frozen; background and amplitude only
  model.freeze("mu");
  model.freeze("sigma");
  await fit(model, data);

  // Step 2: everything free
  model.thaw("mu");
  model.thaw("sigma");
  return fit(model, data);
}

Future<void> main() async {
  // Peak at 7 with width 0.4 on a background of 1, noise 0.05
  final random = Random(4);
  final x = [for (int i = 0; i <= 100; i++) i / 10];
  final y = [
    for (final xi in x)
      1 +
          2 * exp(-(xi - 7) * (xi - 7) / (2 * 0.16)) +
          0.05 * (2 * random.nextDouble() - 1)
  ];
  final data = XYData(x, y, err: List.filled(x.length, 0.05));

  final model = Peak();
  Map<String, double>? best;
  double bestObjective = double.infinity;
  for (final mu0 in [2.0, 5.0, 8.0]) {
    final r = await fitFrom(model, data, mu0);
    print("start mu = $mu0: objective ${r.objective.toStringAsFixed(1)}, "
        "mu = ${model["mu"].toStringAsFixed(3)}");
    if (r.converged && r.objective < bestObjective) {
      best = r.values;
      bestObjective = r.objective;
    }
  }

  // Restore the best fit into the model
  model.params.setValues(best!);
  print("best: ${model.params}");
}
