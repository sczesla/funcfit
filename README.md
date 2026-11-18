# funcfit

Numerical minimization and parameterized model fitting.

- Function minimization with exchangeable minimizer; Powell's method with bounds is included.
- Parameterized models allow you to freeze, thaw, and bound parameter values,
  and tie them to other parameters
  by arbitrary relations, also between successive fits.
- A model has to compute an objective (e.g., -lnL or chi²) based on
  data at its current parameter values; specific curve models with
  Gaussian or Laplace noise are provided.

More examples are in the [example](example/README.md) folder.

## Libraries

```dart
import 'package:funcfit/funcfit.dart';   // everything (typical use)
import 'package:funcfit/minimize.dart';  // minimization algorithms only
import 'package:funcfit/paramfit.dart';  // parameter and model layer
                                         // (includes minimize.dart)
```


## Fitting a linear model to data

Suppose you have measured values `y` at positions `x`. These data are to be
fitted by a straight line `y = a + b·x` with a priori unknown parameters
`a` (offset) and `b` (slope).

```dart
import 'package:funcfit/funcfit.dart';

/// A CurveModel representing a straight line y = a + b·x with
/// the parameters "a" (offset) and "b" (slope).
class Line extends CurveModel {
  Line() : super(["a", "b"]);

  @override
  List<double> evaluate(List<double> x) {
    // Get current values of a and b
    final a = this["a"], b = this["b"];
    // Compute and return model
    return [for (final xi in x) a + b * xi];
  }
}

Future<void> main() async {
  // Measured values y at positions x, each with an uncertainty of 0.3
  final data = XYData(
    [1, 2, 3, 4, 5, 6],
    [0.1, 1.9, 3.5, 4.1, 4.4, 6.1],
    err: List.filled(6, 0.3),
  );

  final line = Line();
  line["b"] = 1; // starting value; parameters start at 0 by default

  // Treat offset and slope (a,b) as free parameters
  // (free by default; shown for clarity).
  line.thaw("a");
  line.thaw("b");

  // Find optimal values, by default -ln(Likelihood) is minimized
  // with a gaussian error model (weighted least squares).
  final result = await fit(line, data, minimizer: Powell());
  print(result.converged); // true
  print(line["a"]); // about -0.46
  print(line["b"]); // about 1.09

  // Fix the offset at 0 and fit the slope only
  line["a"] = 0;
  line.freeze("a");
  // Powell's method is used by default
  await fit(line, data);
  print(line["b"]); // about 0.98
}
```

**What is done**

- `Line` names its parameters and computes the model value for each `x`
  in `evaluate`. From within `evaluate`, parameters are accessed by name via this:
  `this['parameter name']`. Equivalently, name-based access from outside the class
  works via `line["b"] = 1`.
- `XYData` holds the measurements; `err` are their uncertainties. Without
  `err`, all points contribute equally.
- `fit()` varies the parameters until the objective function is minimized and
  the line matches the data best. By
  default, normally distributed (Gaussian) errors are assumed, i.e.,
  weighted least squares. Afterward, the model holds the best values,
  and `result` tells you whether the fit converged.
- `freeze()` keeps a parameter at its value in the following fits;
  `thaw()` releases it again.

**Going further**: bound a parameter to a range (`line.setBounds("b", 0, 2)`),
tie parameters together (`relate()`), use robust Laplace noise against
outliers (`super(["a", "b"], noise: Noise.laplace)`), or combine models
(`CurveSum`, `CurveProduct`). See the [examples](example/README.md).

**Bounds can make fitting harder** see
[Bounds: avoid them where possible](doc/bounds.md) for why and for
alternatives.


## Using the minimizer directly

If you already have a function to minimize, you can call Powell's method
directly, without parameter names or models:

```dart
import 'dart:math';

import 'package:funcfit/minimize.dart';

Future<void> main() async {
  // Rosenbrock function: minimum f = 0 at (1, 1) in a narrow, curved valley
  double rosenbrock(List<double> p) =>
      (pow(1 - p[0], 2) + 100 * pow(p[1] - p[0] * p[0], 2)).toDouble();

  final r = await powell(
    rosenbrock,
    [-1.2, 1.0], // starting point
    lowerBounds: [-2, null], // p[0] >= -2; p[1] unbounded
    upperBounds: [0.5, null], // p[0] <= 0.5: excludes the free minimum
    rftol: 1e-10,
    aftol: 1e-12,
    maxEvaluations: 10000,
  );

  print(r.status); // PowellStatus.absoluteToleranceReached
  print(r.value); // about [0.5, 0.25]: the minimum on the bound
  print(r.objective); // about 0.25
  print(r.evaluations); // 960
}
```

**Details**

- **Objective:** `double Function(List<double>)`. The list is read-only;
  copy it with `List.of()` if needed. Powell's method needs no
  derivatives, but assumes a reasonably smooth function.
- **Non-smooth objectives:** at kinks (e.g., absolute values as in Laplace
  noise, clipping, piecewise defined models), the search can stall and
  report convergence slightly above the minimum; tighter tolerances do not
  necessarily help. Check by fitting again from the result or from other
  start values; if precision matters, smooth the objective (e.g.,
  pseudo-Huber instead of absolute values).
- **Bounds:** per variable, `null` for none. The function is never
  evaluated outside the bounds. A starting point outside them throws an
  `ArgumentError`. Minima on a bound are found exactly. Before accepting
  convergence there, the search checks the neighborhood just inside the
  bound, so a parameter stuck on its bound (e.g., an amplitude at 0 that
  makes the phase irrelevant) does not end the search.
- **Convergence:** an iteration (one line search along every direction)
  that decreases the function by less than `aftol` (absolute) or `rftol`
  (relative) ends the search. `xtol` sets the precision of the line
  searches in units of the direction lengths; `initialScale` sets the
  initially assumed scale of the problem along the individual parameter
  directions (default 1 per variable).
- **Result:** always the best point found, also without convergence;
  check `r.converged` or `r.status` (tolerance reached, `maxIterations`,
  `maxEvaluations`, stopped by callback).
- **Asynchronous:** `powell()` returns a `Future` and yields to the event
  loop once per iteration, so UIs can stay responsive. `onIteration`
  receives the progress after each iteration and stops the search by
  returning `false`, e.g. for a cancel button.
- **With models:** the class `Powell` holds the same options and is the
  default `Minimizer` of `fit()`:
  `fit(model, data, minimizer: Powell(xtol: 1e-6))`.
