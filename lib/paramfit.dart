/// Parameter and model layer on top of the minimization algorithms:
/// named parameters that can be frozen, thawed, limited, and related
/// (`ParameterSet`), models (`Model`, `CurveModel`, `CurveSum`,
/// `CurveProduct`), data (`XYData`), log-likelihoods, and `fit()`.
///
/// Re-exports `minimize.dart`.
library;

export 'minimize.dart';
export 'src/paramfit/composites.dart';
export 'src/paramfit/curve_model.dart';
export 'src/paramfit/data.dart';
export 'src/paramfit/fit.dart';
export 'src/paramfit/likelihoods.dart';
export 'src/paramfit/model.dart';
export 'src/paramfit/parameters.dart';
