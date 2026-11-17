import 'dart:collection';
import 'dart:typed_data';

/// Fixed-length vector of doubles with the element-wise operations used by
/// `powell()`.
///
/// Internal to the package (not exported). The elements are stored in a
/// [Float64List]; all operations return new vectors.
class Vector {
  /// Vector of [n] zeros.
  Vector.zeros(int n) : _data = Float64List(n);

  /// Vector holding a copy of [values].
  Vector.fromList(List<double> values) : _data = Float64List.fromList(values);

  Vector._(this._data);

  final Float64List _data;

  /// Read-only view of the elements (no copy). Changes to this vector, e.g.
  /// via `[]=`, are visible through the view.
  List<double> get data => UnmodifiableListView(_data);

  /// Modifiable copy of the elements.
  List<double> toList() => List<double>.of(_data);

  /// Number of elements.
  int get length => _data.length;

  /// Element [i].
  double operator [](int i) => _data[i];

  /// Sets element [i].
  void operator []=(int i, double value) => _data[i] = value;

  /// Vector times scalar.
  ///
  /// Only this order is possible: `scalar * vector` cannot be defined in
  /// Dart, because `double` has its own `*` operator, which an extension
  /// cannot override.
  Vector operator *(double alpha) {
    final r = Float64List(length);
    for (int i = 0; i < length; i++) {
      r[i] = _data[i] * alpha;
    }
    return Vector._(r);
  }

  /// Element-wise sum. Throws an [ArgumentError] if the lengths differ.
  Vector operator +(Vector other) {
    _checkLength(other, "+");
    final r = Float64List(length);
    for (int i = 0; i < length; i++) {
      r[i] = _data[i] + other._data[i];
    }
    return Vector._(r);
  }

  /// Element-wise difference. Throws an [ArgumentError] if the lengths
  /// differ.
  Vector operator -(Vector other) {
    _checkLength(other, "-");
    final r = Float64List(length);
    for (int i = 0; i < length; i++) {
      r[i] = _data[i] - other._data[i];
    }
    return Vector._(r);
  }

  void _checkLength(Vector other, String op) {
    if (other.length != length) {
      throw ArgumentError(
          "Vector $op: lengths differ ($length and ${other.length})");
    }
  }

  @override
  String toString() => _data.toString();
}
