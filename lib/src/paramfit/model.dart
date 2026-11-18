import 'parameters.dart';

/// A model with named parameters that produces the value of an objective
/// for data of type [D] at its current parameter values.
///
/// Subclasses define the parameters (names passed to the constructor) and
/// [objective]. Fitting is done by the external function `fit()`, which
/// varies the free parameters to minimize [objective].
///
/// ```dart
/// class Line extends Model<({List<double> x, List<double> y})> {
///   Line() : super(["a", "b"]);
///
///   @override
///   double objective(({List<double> x, List<double> y}) d) {
///     final a = this["a"], b = this["b"];
///     double chi2 = 0;
///     for (int i = 0; i < d.x.length; i++) {
///       final r = d.y[i] - (a + b * d.x[i]);
///       chi2 += r * r;
///     }
///     return chi2;
///   }
/// }
/// ```
///
/// The operators and methods below pass through to [params]; everything
/// else is available there. Inside loops over data, read parameter values
/// once beforehand: each access is a lookup by name.
abstract class Model<D> {
  /// Creates a model with one parameter per name (free, value 0, no bounds)
  /// and, for composite models, the parameter sets of its components as
  /// labeled [children] (references, not copies). See [ParameterSet].
  Model(List<String> names, {Map<String, ParameterSet> children = const {}})
      : params = ParameterSet(names, children: children);

  /// The parameters of the model.
  final ParameterSet params;

  /// Value to be minimized (e.g., -lnL or chi²) for [data] at the current
  /// parameter values.
  double objective(D data);

  /// Value of the parameter called [name].
  double operator [](String name) => params[name];

  /// Sets the value of the parameter called [name].
  void operator []=(String name, double value) => params[name] = value;

  /// Freezes the parameter called [name]. See [ParameterSet.freeze].
  void freeze(String name) => params.freeze(name);

  /// Makes the parameter called [name] free. See [ParameterSet.thaw].
  void thaw(String name) => params.thaw(name);

  /// Sets the bounds of the parameter called [name]. See
  /// [ParameterSet.setBounds].
  void setBounds(String name, double? lower, double? upper) =>
      params.setBounds(name, lower, upper);

  /// Makes the parameter called [target] a function of the parameters called
  /// [sources]. See [ParameterSet.relate].
  void relate(String target, List<String> sources,
          double Function(List<double> sourceValues) function,
          {String? description}) =>
      params.relate(target, sources, function, description: description);

  /// Removes the relation of the parameter called [target]. See
  /// [ParameterSet.removeRelation].
  void removeRelation(String target) => params.removeRelation(target);

  @override
  String toString() => "$runtimeType: $params";
}
