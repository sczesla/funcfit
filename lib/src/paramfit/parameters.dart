import 'dart:collection';
import 'dart:math';

/// State of a [Parameter].
enum ParameterState {
  /// Varied by the optimizer.
  free,

  /// Keeps its value.
  frozen,

  /// Computed from other parameters by a [ParameterRelation]; never varied
  /// by the optimizer.
  dependent,
}

/// Checks the rules for parameter names and component labels: non-empty,
/// no `.` (the separator of qualified names).
void _checkName(String name, String what) {
  if (name.isEmpty) {
    throw ArgumentError.value(name, what, "Must not be empty");
  }
  if (name.contains('.')) {
    throw ArgumentError.value(name, what, "Must not contain '.'");
  }
}

/// Relation making a parameter (the target) a function of other parameters
/// (the [sources]). See [Parameter.relate].
class ParameterRelation {
  ParameterRelation._(List<Parameter> sources, this.function, this.description)
      : sources = List.unmodifiable(sources);

  /// The parameters the target depends on, in the order in which their
  /// values are passed to [function].
  final List<Parameter> sources;

  /// Computes the value of the target from the values of the [sources].
  final double Function(List<double> sourceValues) function;

  /// Human-readable description (e.g., `g1.mu + 1.5`), or null.
  final String? description;

  double _evaluate() => function([for (final s in sources) s.value]);
}

/// A named model parameter with a value, a state (free, frozen, or
/// dependent), and optional lower and upper bounds.
///
/// Free parameters are varied by the optimizer; frozen ones keep their
/// [value]; the value of a dependent parameter is computed from other
/// parameters by its [relation] whenever it is read.
///
/// The bounds are not enforced by the parameter itself; the fitting code
/// passes them to the minimizer as bounds, or an objective can add
/// [boundPenalty].
class Parameter {
  /// Creates a parameter, free unless [free] is false.
  ///
  /// Throws an [ArgumentError] if [name] is empty or contains `.`, or if the
  /// bounds are invalid (see [setBounds]).
  Parameter(this.name, double value,
      {bool free = true, double? lower, double? upper})
      : _value = value,
        _free = free {
    _checkName(name, "name");
    setBounds(lower, upper);
  }

  /// Creates a copy of [p] with the same name, value, state, bounds, and
  /// relation. The relation still refers to the source parameters of [p];
  /// [ParameterSet.copy] remaps relations within a set.
  Parameter.copy(Parameter p)
      : name = p.name,
        _value = p._value,
        _free = p._free,
        _lower = p._lower,
        _upper = p._upper,
        _relation = p._relation;

  /// Name of the parameter, unique within one level of a [ParameterSet].
  final String name;

  double _value;
  bool _free;
  double? _lower;
  double? _upper;
  ParameterRelation? _relation;

  /// Current value; for a dependent parameter computed from its sources.
  double get value => _relation?._evaluate() ?? _value;

  /// Sets the value. Throws an [ArgumentError] for a dependent parameter.
  set value(double v) {
    _checkNotDependent("set the value of");
    _value = v;
  }

  /// Current state.
  ParameterState get state => _relation != null
      ? ParameterState.dependent
      : (_free ? ParameterState.free : ParameterState.frozen);

  /// The relation of a dependent parameter, or null.
  ParameterRelation? get relation => _relation;

  /// Lower bound, or null if there is none.
  double? get lower => _lower;

  /// Upper bound, or null if there is none.
  double? get upper => _upper;

  void _checkNotDependent(String action) {
    if (_relation != null) {
      throw ArgumentError(
          "$name: cannot $action a dependent parameter; remove the relation "
          "first");
    }
  }

  /// Makes the parameter free. Throws an [ArgumentError] if it is dependent.
  void thaw() {
    _checkNotDependent("thaw");
    _free = true;
  }

  /// Freezes the parameter at its current value. Throws an [ArgumentError]
  /// if it is dependent.
  void freeze() {
    _checkNotDependent("freeze");
    _free = false;
  }

  /// Sets the bounds; null means no bound.
  ///
  /// Bounds are hard edges for the fit; avoid them where possible and use
  /// them mainly where the model is undefined or impossible. Equivalent
  /// solutions (a phase and the phase plus one period, the sign of an
  /// amplitude) are better handled by post-processing or
  /// reparameterization; see
  /// [Bounds: avoid them where possible](https://github.com/sczesla/funcfit/blob/main/doc/bounds.md).
  ///
  /// Throws an [ArgumentError] if a bound is NaN, if [lower] > [upper], or
  /// if the parameter is dependent and a bound is given.
  void setBounds(double? lower, double? upper) {
    if (lower != null && lower.isNaN) {
      throw ArgumentError.value(lower, "lower", "$name: must not be NaN");
    }
    if (upper != null && upper.isNaN) {
      throw ArgumentError.value(upper, "upper", "$name: must not be NaN");
    }
    if (lower != null && upper != null && lower > upper) {
      throw ArgumentError(
          "$name: lower bound ($lower) is greater than upper bound ($upper)");
    }
    if (_relation != null && (lower != null || upper != null)) {
      throw ArgumentError("$name: a dependent parameter cannot have bounds");
    }
    _lower = lower;
    _upper = upper;
  }

  /// Makes this parameter dependent: its value becomes
  /// `function(values of sources)`, computed whenever it is read.
  ///
  /// Throws an [ArgumentError] if the parameter is already dependent, if it
  /// has bounds, or if the relation would create a cycle (including this
  /// parameter being one of its own sources).
  void relate(List<Parameter> sources,
      double Function(List<double> sourceValues) function,
      {String? description}) {
    if (_relation != null) {
      throw ArgumentError(
          "$name: already dependent; remove the relation first");
    }
    if (_lower != null || _upper != null) {
      throw ArgumentError(
          "$name: a parameter with bounds cannot become dependent");
    }
    // Follow the source references; reaching this parameter means a cycle
    final visited = HashSet<Parameter>.identity();
    final stack = [...sources];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      if (identical(p, this)) {
        throw ArgumentError("$name: the relation would create a cycle");
      }
      if (!visited.add(p)) continue;
      final r = p._relation;
      if (r != null) stack.addAll(r.sources);
    }
    _relation = ParameterRelation._(sources, function, description);
  }

  /// Removes the relation: the parameter becomes free and keeps the last
  /// computed value. Does nothing if the parameter is not dependent.
  void removeRelation() {
    final r = _relation;
    if (r == null) return;
    _value = r._evaluate();
    _relation = null;
    _free = true;
  }

  String _describe(String displayName) {
    final bounds = (lower != null || upper != null)
        ? " in [${lower ?? '-inf'}, ${upper ?? 'inf'}]"
        : "";
    final stateText = switch (state) {
      ParameterState.free => "",
      ParameterState.frozen => " (frozen)",
      ParameterState.dependent =>
        " (dependent${_relation!.description != null ? ': ${_relation!.description}' : ''})",
    };
    return "$displayName = $value$stateText$bounds";
  }

  @override
  String toString() => _describe(name);
}

/// An ordered, possibly nested set of named [Parameter]s of a model.
///
/// A set consists of its own parameters and, for composite models, labeled
/// child sets. Child sets are referenced, not copied: a change made through
/// a child set or through the composite affects the same [Parameter]
/// object. Parameters of child sets are addressed by qualified names
/// `label.name` (nested: `outer.inner.name`).
///
/// The order of the parameters, which is the order in which `powell()` sees
/// the free ones, is: own parameters in the order of the names given to the
/// constructor, then the child sets depth-first in the order of their
/// labels.
///
/// ```dart
/// // Start values for the optimizer
/// final p0 = params.freeValues();
///
/// // In the objective: map the optimizer's values back to the parameters
/// double objective(List<double> vals) {
///   params.setFreeValues(vals);
///   ...
/// }
/// ```
///
/// New parameters are free, have value 0, and no bounds. Methods taking a
/// parameter name accept qualified names and throw an [ArgumentError] for
/// unknown names.
class ParameterSet {
  /// Creates a set with one parameter per name, in the given order, and the
  /// given labeled child sets.
  ///
  /// Throws an [ArgumentError] if a name or label is empty or contains `.`,
  /// if a name occurs more than once, if a label equals the name of an own
  /// parameter, or if the same [Parameter] object would occur more than
  /// once in the set (e.g., the same child set under two labels).
  ParameterSet(List<String> names,
      {Map<String, ParameterSet> children = const {}}) {
    for (final name in names) {
      _checkName(name, "names");
      if (_own.containsKey(name)) {
        throw ArgumentError.value(name, "names", "Duplicate parameter name");
      }
      _own[name] = Parameter(name, 0.0);
    }
    _addChildren(children);
  }

  ParameterSet._empty();

  void _addChildren(Map<String, ParameterSet> children) {
    for (final MapEntry(key: label, value: child) in children.entries) {
      _checkName(label, "children");
      if (_own.containsKey(label)) {
        throw ArgumentError.value(
            label, "children", "Label equals the name of a parameter");
      }
      _children[label] = child;
    }
    final seen = HashSet<Parameter>.identity();
    for (final p in parameters) {
      if (!seen.add(p)) {
        throw ArgumentError(
            "Parameter '${p.name}' occurs more than once in the set");
      }
    }
  }

  // Map literals keep insertion order, which defines the parameter order.
  final Map<String, Parameter> _own = {};
  final Map<String, ParameterSet> _children = {};

  /// Labels of the child sets, in order.
  List<String> get labels => List.unmodifiable(_children.keys);

  /// The child set with the given [label].
  ParameterSet child(String label) =>
      _children[label] ??
      (throw ArgumentError.value(label, "label", "Unknown child set"));

  /// All parameters with their qualified names, in order.
  Iterable<(String, Parameter)> _entries([String prefix = ""]) sync* {
    for (final p in _own.values) {
      yield ("$prefix${p.name}", p);
    }
    for (final MapEntry(key: label, value: child) in _children.entries) {
      yield* child._entries("$prefix$label.");
    }
  }

  /// Qualified names of all parameters, in order.
  List<String> get names => List.unmodifiable(_entries().map((e) => e.$1));

  /// All parameters, in order.
  Iterable<Parameter> get parameters => _entries().map((e) => e.$2);

  /// The parameter called [name] (a qualified name for parameters of child
  /// sets).
  Parameter parameter(String name) {
    final own = _own[name];
    if (own != null) return own;
    final dot = name.indexOf('.');
    if (dot > 0) {
      final child = _children[name.substring(0, dot)];
      if (child != null) {
        try {
          return child.parameter(name.substring(dot + 1));
        } on ArgumentError {
          // Report the full name below
        }
      }
    }
    throw ArgumentError.value(name, "name", "Unknown parameter");
  }

  /// Value of the parameter called [name].
  double operator [](String name) => parameter(name).value;

  /// Sets the value of the parameter called [name]. Throws an
  /// [ArgumentError] if it is dependent.
  void operator []=(String name, double value) => parameter(name).value = value;

  /// Sets the values of several parameters by name.
  ///
  /// All names are checked first (unknown or dependent parameters throw an
  /// [ArgumentError]); if any check fails, no value is changed.
  void setValues(Map<String, double> values) {
    final targets = [
      for (final MapEntry(key: name, value: v) in values.entries)
        (parameter(name), v)
    ];
    for (final (p, _) in targets) {
      p._checkNotDependent("set the value of");
    }
    for (final (p, v) in targets) {
      p.value = v;
    }
  }

  /// Makes the parameter called [name] free. See [Parameter.thaw].
  void thaw(String name) => parameter(name).thaw();

  /// Freezes the parameter called [name]. See [Parameter.freeze].
  void freeze(String name) => parameter(name).freeze();

  /// Sets the bounds of the parameter called [name]; null means no bound.
  /// See [Parameter.setBounds].
  void setBounds(String name, double? lower, double? upper) =>
      parameter(name).setBounds(lower, upper);

  /// Makes the parameter called [target] a function of the parameters
  /// called [sources]: its value becomes `function(values of sources)`.
  /// See [Parameter.relate].
  ///
  /// ```dart
  /// params.relate('g2.sigma', ['g1.sigma'], (v) => v[0]); // tie
  /// params.relate('g2.mu', ['g1.mu'], (v) => v[0] + 1.5,
  ///     description: 'g1.mu + 1.5');
  /// ```
  void relate(String target, List<String> sources,
          double Function(List<double> sourceValues) function,
          {String? description}) =>
      parameter(target).relate(
          [for (final s in sources) parameter(s)], function,
          description: description);

  /// Removes the relation of the parameter called [target]; it becomes free.
  /// See [Parameter.removeRelation].
  void removeRelation(String target) => parameter(target).removeRelation();

  Iterable<(String, Parameter)> _freeEntries() =>
      _entries().where((e) => e.$2.state == ParameterState.free);

  /// Qualified names of the free parameters, in order.
  List<String> freeNames() => [for (final (n, _) in _freeEntries()) n];

  /// Values of the free parameters, in order (e.g., start values for
  /// `powell()`).
  List<double> freeValues() => [for (final (_, p) in _freeEntries()) p.value];

  /// Values of the free parameters by qualified name, in order.
  Map<String, double> freeValuesByName() =>
      {for (final (n, p) in _freeEntries()) n: p.value};

  /// Lower bounds of the free parameters, in order (null: no bound), e.g.,
  /// as `lowerBounds` for `powell()`.
  List<double?> freeLowerBounds() =>
      [for (final (_, p) in _freeEntries()) p.lower];

  /// Upper bounds of the free parameters, in order (null: no bound), e.g.,
  /// as `upperBounds` for `powell()`.
  List<double?> freeUpperBounds() =>
      [for (final (_, p) in _freeEntries()) p.upper];

  /// Assigns [values] to the free parameters, in order (the inverse of
  /// [freeValues]).
  ///
  /// Throws an [ArgumentError] if the number of values differs from the
  /// number of free parameters; no value is changed then.
  void setFreeValues(List<double> values) {
    final free = [for (final (_, p) in _freeEntries()) p];
    if (free.length != values.length) {
      throw ArgumentError("Got ${values.length} values, but there are "
          "${free.length} free parameters");
    }
    for (int i = 0; i < free.length; i++) {
      free[i]._value = values[i];
    }
  }

  /// Returns an independent (deep) copy with the same structure, e.g., to
  /// keep the parameters of the best fit while the optimizer continues to
  /// change this set.
  ///
  /// Relations whose sources belong to this set are remapped to the copied
  /// parameters; sources outside the set are still referenced.
  ParameterSet copy() {
    final mapping = HashMap<Parameter, Parameter>.identity();
    final c = _copyStructure(mapping);
    for (final MapEntry(key: old, value: p) in mapping.entries) {
      final r = old._relation;
      if (r != null) {
        p._relation = ParameterRelation._(
            [for (final s in r.sources) mapping[s] ?? s],
            r.function,
            r.description);
      }
    }
    return c;
  }

  ParameterSet _copyStructure(Map<Parameter, Parameter> mapping) {
    final c = ParameterSet._empty();
    for (final p in _own.values) {
      final pc = Parameter.copy(p);
      mapping[p] = pc;
      c._own[p.name] = pc;
    }
    for (final MapEntry(key: label, value: child) in _children.entries) {
      c._children[label] = child._copyStructure(mapping);
    }
    return c;
  }

  @override
  String toString() =>
      [for (final (n, p) in _entries()) p._describe(n)].join(", ");
}

/// Penalty for parameters outside their bounds, to be added to the function
/// minimized (or subtracted from a log-likelihood).
///
/// For each parameter, free or frozen, that lies a distance d > 0 beyond one
/// of its bounds, the penalty is
///
///     exp(min(d / expScale, 10)) - 1 + linScale * d
///
/// It is 0 within the bounds and continuous at the bounds. The exponential
/// term rises steeply within the first `10 * expScale` beyond a bound and
/// then stays at e^10 - 1 (about 22025); the linear term keeps growing, so
/// that the optimizer is pushed back towards the allowed range from any
/// distance.
///
/// [expScale] sets the distance over which the exponential term rises; it
/// should be small compared to the typical scale of the parameters.
/// Throws an [ArgumentError] if it is not positive and finite.
double boundPenalty(ParameterSet params,
    {double linScale = 1e6, double expScale = 1e-5}) {
  if (!(expScale > 0 && expScale.isFinite)) {
    throw ArgumentError.value(
        expScale, "expScale", "Must be positive and finite");
  }
  double penalty = 0;
  for (final p in params.parameters) {
    final lower = p.lower;
    final upper = p.upper;
    final value = p.value;
    if (lower != null && value < lower) {
      final d = lower - value;
      penalty += exp(min(d / expScale, 10)) - 1.0 + d * linScale;
    }
    if (upper != null && value > upper) {
      final d = value - upper;
      penalty += exp(min(d / expScale, 10)) - 1.0 + d * linScale;
    }
  }
  return penalty;
}
