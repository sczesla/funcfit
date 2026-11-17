/// Derivative-free minimization algorithms: Powell's method (`powell()`,
/// `Powell`) and golden section line search (`goldenSection()`), with the
/// `Minimizer` interface for exchangeable algorithms.
///
/// Does not depend on the parameter and model layer (`paramfit.dart`).
library;

export 'src/minimize/golden_section.dart';
export 'src/minimize/minimizer.dart';
export 'src/minimize/powell.dart';
