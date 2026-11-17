// Following the progress of a minimization and cancelling it.
//
// powell() (and the Powell minimizer used by fit()) calls onIteration
// after every iteration with the current state. Returning false stops the
// search; the result then holds the best point found so far, with status
// stoppedByCallback. Because powell() yields to the event loop once per
// iteration, a flag set elsewhere (e.g., by a cancel button in a UI, here
// by a timer) is seen at the next iteration.
//
// Run with: dart run example/progress_and_cancel.dart

import 'dart:async';
import 'dart:math';

import 'package:funcfit/minimize.dart';

/// Extended Rosenbrock function in [n] dimensions: minimum 0 at (1, ..., 1).
double rosenbrock(List<double> p) {
  double s = 0;
  for (int i = 0; i < p.length - 1; i++) {
    s += 100 * pow(p[i + 1] - p[i] * p[i], 2) + pow(1 - p[i], 2);
  }
  return s;
}

Future<void> main() async {
  final start = List.filled(10, -1.0);

  // 1. Progress: print every 10th iteration, run to convergence
  final r1 = await powell(rosenbrock, start,
      rftol: 1e-10, aftol: 1e-12, maxIterations: 1000, onIteration: (p) {
    if (p.iteration % 10 == 0) {
      print(
          "iteration ${p.iteration}: f = ${p.objective.toStringAsExponential(3)}"
          " after ${p.evaluations} evaluations");
    }
    return true; // continue
  });
  print("${r1.status.name}: f = ${r1.objective}\n");

  // 2. Cancellation: a timer stands in for a cancel button and sets a flag
  //    after 2 ms (the whole search takes longer); the callback reads it
  bool cancelled = false;
  Timer(const Duration(milliseconds: 2), () => cancelled = true);
  final r2 = await powell(rosenbrock, start,
      rftol: 1e-10,
      aftol: 1e-12,
      maxIterations: 1000,
      onIteration: (p) => !cancelled);
  print("${r2.status.name} after ${r2.iterations} iterations: "
      "f = ${r2.objective}");

  // With models, pass the same callback to the minimizer of fit():
  //   fit(model, data, minimizer: Powell(onIteration: (p) => !cancelled));
}
