/// Derivative-free minimization: Powell's method (`powell()`, `Powell`)
/// with golden section line search, and the `Minimizer` interface for
/// exchangeable algorithms.
///
/// Does not depend on the parameter and model layer (`paramfit.dart`).
library;

export 'src/minimize/minimizer.dart';
export 'src/minimize/powell.dart';
