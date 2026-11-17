import 'dart:collection';

import '../minimize/minimizer.dart';
import 'model.dart';
import 'parameters.dart';
import '../minimize/powell.dart';

/// Result of [fit].
class FitResult {
  /// Creates a result; normally done by [fit].
  FitResult(this.minimizerResult, Map<String, double> values)
      : values = Map.unmodifiable(values);

  /// What the minimizer reported (e.g., a `PowellResult` with further
  /// details).
  final MinimizerResult minimizerResult;

  /// Values of all parameters (free, frozen, and dependent) after the fit,
  /// by qualified name, in order.
  final Map<String, double> values;

  /// Value of the objective at the best fit.
  double get objective => minimizerResult.objective;

  /// Whether the minimizer met a convergence criterion.
  bool get converged => minimizerResult.converged;

  /// The minimizer's description of the outcome.
  String get message => minimizerResult.message;

  @override
  String toString() =>
      "FitResult: $message, objective = $objective, values = $values";
}

/// Fits [model] to [data]: varies the free parameters of the model with
/// [minimizer] to minimize `model.objective(data)`.
///
/// - The limits of the free parameters are passed to the minimizer as
///   bounds (none are passed if no free parameter has limits).
/// - Afterwards, the parameters of the model hold the best fit; dependent
///   parameters follow their relations.
/// - If the minimizer throws, the start values are restored and the
///   exception is rethrown.
///
/// Throws an [ArgumentError] if the model has no free parameters, if the
/// value of a free parameter lies outside its limits, or if a relation of a
/// dependent parameter refers to a parameter outside the model.
Future<FitResult> fit<D>(Model<D> model, D data,
    {Minimizer minimizer = const Powell()}) async {
  final params = model.params;

  // Relations must stay within the model
  final names = params.names;
  final all = params.parameters.toList();
  final inModel = HashSet<Parameter>.identity()..addAll(all);
  for (int i = 0; i < all.length; i++) {
    for (final s in all[i].relation?.sources ?? const <Parameter>[]) {
      if (!inModel.contains(s)) {
        throw ArgumentError("The relation of '${names[i]}' refers to the "
            "parameter '${s.name}' outside the model");
      }
    }
  }

  final freeNames = params.freeNames();
  if (freeNames.isEmpty) {
    throw ArgumentError("The model has no free parameters");
  }
  final start = params.freeValues();
  final lower = params.freeLowerBounds();
  final upper = params.freeUpperBounds();
  for (int i = 0; i < start.length; i++) {
    final lo = lower[i], hi = upper[i];
    if ((lo != null && !(start[i] >= lo)) ||
        (hi != null && !(start[i] <= hi))) {
      throw ArgumentError("The value of '${freeNames[i]}' (${start[i]}) is "
          "not within its limits [${lo ?? '-inf'}, ${hi ?? 'inf'}]");
    }
  }
  final bounded = lower.any((b) => b != null) || upper.any((b) => b != null);

  final MinimizerResult result;
  try {
    result = await minimizer.minimize((v) {
      params.setFreeValues(v);
      return model.objective(data);
    }, start, lower: bounded ? lower : null, upper: bounded ? upper : null);
  } catch (_) {
    params.setFreeValues(start);
    rethrow;
  }
  params.setFreeValues(result.value);
  return FitResult(result, {for (final n in names) n: params[n]});
}
