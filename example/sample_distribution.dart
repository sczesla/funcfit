// Estimating the parameters of a distribution from a sample.
//
// Not every model is a curve compared with x/y data. Here, the data are a
// plain list of measured values, and the model is a normal distribution
// whose mean and standard deviation are estimated by maximum likelihood.
// A model only has to provide `objective`: the value to be minimized for
// the data at its current parameter values.
//
// Run with: dart run example/sample_distribution.dart

import 'dart:math';

import 'package:funcfit/funcfit.dart';

/// Normal distribution with mean "mu" and standard deviation "sigma".
/// The data are a sample (`List<double>`), not x/y pairs.
class NormalDistribution extends Model<List<double>> {
  NormalDistribution() : super(["mu", "sigma"]) {
    // The standard deviation must be positive
    setBounds("sigma", 1e-9, null);
  }

  /// Negative log-likelihood of the sample.
  @override
  double objective(List<double> sample) {
    final mu = this["mu"], sigma = this["sigma"];
    double nlnL = 0;
    for (final x in sample) {
      final z = (x - mu) / sigma;
      nlnL += 0.5 * z * z + log(sigma) + 0.5 * log(2 * pi);
    }
    return nlnL;
  }
}

Future<void> main() async {
  // Sample of 200 values from a normal distribution (mean 5, sd 2)
  final random = Random(1);
  final sample = [
    for (int i = 0; i < 200; i++)
      5 +
          2 *
              sqrt(-2 * log(1 - random.nextDouble())) *
              cos(2 * pi * random.nextDouble())
  ];

  final model = NormalDistribution();
  model["sigma"] = 1; // start value within the bound
  final result = await fit(model, sample);
  print(result);

  // For the normal distribution, the maximum-likelihood estimates are
  // known in closed form: the mean and the (biased) standard deviation
  final mean = sample.reduce((a, b) => a + b) / sample.length;
  final sd = sqrt(
      sample.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
          sample.length);
  print("closed form: mu = $mean, sigma = $sd");
}
