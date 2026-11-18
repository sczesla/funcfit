/// Fitting models with named parameters (free, frozen, bounded, or
/// dependent) to data, on top of exchangeable derivative-free minimization
/// algorithms (Powell's method with golden section line search).
///
/// This library exports everything: the parameter and model layer
/// (`paramfit.dart`) and the algorithms (`minimize.dart`), which can also be
/// imported on their own.
library;

export 'paramfit.dart';
