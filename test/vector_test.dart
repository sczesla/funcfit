import 'package:funcfit/src/minimize/vector.dart';
import 'package:test/test.dart';

void main() {
  group('Vector', () {
    test('zeros and fromList', () {
      expect(Vector.zeros(3).data, [0.0, 0.0, 0.0]);
      expect(Vector.fromList([1.5, -2]).data, [1.5, -2.0]);
      expect(Vector.zeros(0).length, 0);
    });

    test('fromList copies its input', () {
      final l = [1.0, 2.0];
      final v = Vector.fromList(l);
      l[0] = 99;
      expect(v[0], 1.0);
    });

    test('data is a read-only view, toList a modifiable copy', () {
      final v = Vector.fromList([1.0, 2.0]);
      expect(() => v.data[0] = 5, throwsUnsupportedError);
      final c = v.toList();
      c[0] = 5;
      expect(v[0], 1.0);
      // The view reflects changes to the vector
      final view = v.data;
      v[1] = 7;
      expect(view[1], 7.0);
    });

    test('operators', () {
      final a = Vector.fromList([1, 2, 3]);
      final b = Vector.fromList([0.5, -1, 4]);
      expect((a + b).data, [1.5, 1.0, 7.0]);
      expect((a - b).data, [0.5, 3.0, -1.0]);
      expect((a * 2).data, [2.0, 4.0, 6.0]);
      expect((a * 2 - b).data, [1.5, 5.0, 2.0]);
      // Operands unchanged
      expect(a.data, [1.0, 2.0, 3.0]);
      expect(b.data, [0.5, -1.0, 4.0]);
    });

    test('different lengths throw', () {
      final a = Vector.fromList([1, 2, 3]);
      final b = Vector.fromList([1, 2]);
      expect(() => a + b, throwsArgumentError);
      expect(() => b + a, throwsArgumentError);
      expect(() => a - b, throwsArgumentError);
    });

    test('index access', () {
      final v = Vector.zeros(2);
      v[1] = 3;
      expect(v[1], 3.0);
      expect(() => v[2], throwsRangeError);
    });

    test('toString', () {
      expect(Vector.fromList([1, 2]).toString(), "[1.0, 2.0]");
    });
  });
}
