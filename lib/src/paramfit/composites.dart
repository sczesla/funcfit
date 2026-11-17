import 'curve_model.dart';
import 'parameters.dart';

/// Sum of curve models: the curve is the sum of the components' curves.
///
/// A `CurveSum` is itself a [CurveModel], so it can be a component of
/// another `CurveSum` or a [CurveProduct].
///
/// ```dart
/// final line = Line();
/// final g1 = Gaussian();
/// final sum = CurveSum({'line': line, 'g1': g1});
/// sum['g1.mu'] = 3.0;                // same parameter as g1['mu']
/// sum.relate('g1.sigma', ['line.b'], (v) => 2 * v[0]);
/// await fit(sum, data);              // line and g1 hold the best fit
/// ```
///
/// - The parameters of the components are referenced, not copied:
///   `sum['g1.mu']` and `g1['mu']` are the same parameter, and fitting the
///   sum changes the components. Copy a component's parameters before
///   combining if they must stay unchanged.
/// - Parameter order: the components in the order of [components], each
///   with its parameters in order.
/// - The noise model of the sum ([noise]) applies; the noise settings of the
///   components are ignored.
/// - There is no difference class: let the subtracted component carry the
///   sign itself (e.g., a negative amplitude, or an absorption line
///   defined as `-depth * profile`).
/// - The sum is exact also for components that average over intervals
///   themselves (interval data), because the mean of a sum is the sum of
///   the means.
class CurveSum extends CurveModel {
  /// Creates the sum of [components], labeled by the map keys.
  ///
  /// Throws an [ArgumentError] if [components] is empty, if a label is
  /// empty or contains `.`, or if the same component (or parameter) occurs
  /// more than once.
  CurveSum(Map<String, CurveModel> components, {super.noise})
      : components = Map.unmodifiable(components),
        super(const [], children: _children(components));

  /// The components by label, in order.
  final Map<String, CurveModel> components;

  /// Sum of the components' curves.
  ///
  /// Throws an [ArgumentError] if the components return curves of different
  /// lengths.
  @override
  List<double> evaluate(List<double> x) =>
      _combine("CurveSum", components, x, (a, b) => a + b);
}

/// Product of curve models: the curve is the product of the components'
/// curves, e.g., a spectrum times a transmission curve, or a profile
/// times a time-dependent amplitude.
///
/// A `CurveProduct` is itself a [CurveModel], so it can be a component of
/// another `CurveProduct` or a [CurveSum]:
///
/// ```dart
/// // (continuum + line) * transmission
/// final model = CurveProduct({
///   'source': CurveSum({'continuum': continuum, 'line': line}),
///   'transmission': transmission,
/// });
/// ```
///
/// Parameters, order, and noise model behave as for [CurveSum].
///
/// - A product contains degenerate parameters if more than one component
///   has a free scale factor (only the product of the factors is
///   determined): freeze or relate all but one of them.
/// - There is no ratio class: let the divisor component compute the
///   reciprocal itself, or write a combination of your own (a
///   [CurveModel] with the components' parameter sets as `children`, as
///   `CurveSum` does).
/// - **Not exact for interval data:** if the components average over
///   intervals themselves, the product of the means is not the mean of the
///   product. A product of interval averages is only an approximation,
///   good where all but one component vary little within an interval.
class CurveProduct extends CurveModel {
  /// Creates the product of [components], labeled by the map keys.
  ///
  /// Throws an [ArgumentError] if [components] is empty, if a label is
  /// empty or contains `.`, or if the same component (or parameter) occurs
  /// more than once.
  CurveProduct(Map<String, CurveModel> components, {super.noise})
      : components = Map.unmodifiable(components),
        super(const [], children: _children(components));

  /// The components by label, in order.
  final Map<String, CurveModel> components;

  /// Product of the components' curves.
  ///
  /// Throws an [ArgumentError] if the components return curves of different
  /// lengths.
  @override
  List<double> evaluate(List<double> x) =>
      _combine("CurveProduct", components, x, (a, b) => a * b);
}

/// The components' parameter sets as children labeled by the map keys;
/// throws an [ArgumentError] for an empty map.
Map<String, ParameterSet> _children(Map<String, CurveModel> components) {
  if (components.isEmpty) {
    throw ArgumentError.value(components, "components", "Must not be empty");
  }
  return {
    for (final MapEntry(key: label, value: c) in components.entries)
      label: c.params
  };
}

/// Combines the components' curves pointwise with [op], from left to right.
List<double> _combine(String kind, Map<String, CurveModel> components,
    List<double> x, double Function(double, double) op) {
  List<double>? result;
  for (final MapEntry(key: label, value: c) in components.entries) {
    final v = c.evaluate(x);
    if (result == null) {
      result = List.of(v);
    } else {
      if (v.length != result.length) {
        throw ArgumentError("$kind: component '$label' returned "
            "${v.length} values, the previous ones ${result.length}");
      }
      for (int i = 0; i < result.length; i++) {
        result[i] = op(result[i], v[i]);
      }
    }
  }
  return result!;
}
