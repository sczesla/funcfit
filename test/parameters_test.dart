import 'package:funcfit/funcfit.dart';
import 'package:test/test.dart';

void main() {
  group('Parameter', () {
    test('bounds default to none', () {
      final p = Parameter("a", 1.5);
      expect(p.lower, isNull);
      expect(p.upper, isNull);
      expect(p.state, ParameterState.free);
    });

    test('valid bounds are stored', () {
      final p = Parameter("a", 1.5, lower: -1, upper: 2);
      expect(p.lower, -1);
      expect(p.upper, 2);
      p.setBounds(null, 5);
      expect(p.lower, isNull);
      expect(p.upper, 5);
      p.setBounds(3, 3); // equal bounds are allowed
      expect(p.lower, 3);
    });

    test('invalid bounds throw', () {
      expect(() => Parameter("a", 0, lower: 2, upper: 1), throwsArgumentError);
      expect(() => Parameter("a", 0, lower: double.nan), throwsArgumentError);
      expect(() => Parameter("a", 0, upper: double.nan), throwsArgumentError);
      final p = Parameter("a", 0, lower: 0, upper: 1);
      expect(() => p.setBounds(1, 0), throwsArgumentError);
      // Unchanged after a failed attempt
      expect(p.lower, 0);
      expect(p.upper, 1);
    });

    test('copy is independent', () {
      final p = Parameter("a", 1.5, free: false, lower: 0, upper: 2);
      final c = Parameter.copy(p);
      c.value = 9;
      c.thaw();
      c.setBounds(null, null);
      expect(p.value, 1.5);
      expect(p.state, ParameterState.frozen);
      expect(p.lower, 0);
      expect(p.upper, 2);
    });

    test('toString', () {
      expect(Parameter("a", 1.5).toString(), "a = 1.5");
      expect(Parameter("a", 1.5, free: false, lower: 0).toString(),
          "a = 1.5 (frozen) in [0.0, inf]");
    });
  });

  group('ParameterSet', () {
    ParameterSet make() {
      final s = ParameterSet(["c", "a", "b"]);
      s["c"] = 3;
      s["a"] = 1;
      s["b"] = 2;
      return s;
    }

    test('keeps the order of the names', () {
      final s = make();
      expect(s.names, ["c", "a", "b"]);
      expect(s.parameters.map((p) => p.name), ["c", "a", "b"]);
      expect(s.freeNames(), ["c", "a", "b"]);
      expect(s.freeValues(), [3.0, 1.0, 2.0]);
    });

    test('new parameters are free, 0, without bounds', () {
      final p = ParameterSet(["x"]).parameter("x");
      expect(p.value, 0.0);
      expect(p.state, ParameterState.free);
      expect(p.lower, isNull);
      expect(p.upper, isNull);
    });

    test('duplicate names throw', () {
      expect(() => ParameterSet(["a", "b", "a"]), throwsArgumentError);
    });

    test('unknown names throw ArgumentError', () {
      final s = make();
      expect(() => s["x"], throwsArgumentError);
      expect(() => s["x"] = 1, throwsArgumentError);
      expect(() => s.parameter("x"), throwsArgumentError);
      expect(() => s.freeze("x"), throwsArgumentError);
      expect(() => s.thaw("x"), throwsArgumentError);
      expect(() => s.setBounds("x", 0, 1), throwsArgumentError);
    });

    test('names cannot be modified from outside', () {
      expect(() => make().names.add("x"), throwsUnsupportedError);
    });

    test('freeze and thaw affect the free parameters', () {
      final s = make();
      s.freeze("a");
      expect(s.freeNames(), ["c", "b"]);
      expect(s.freeValues(), [3.0, 2.0]);
      expect(s.freeValuesByName(), {"c": 3.0, "b": 2.0});
      expect(s.freeValuesByName().keys, ["c", "b"]);
      s.thaw("a");
      expect(s.freeNames(), ["c", "a", "b"]);
    });

    test('setFreeValues assigns in order and skips frozen parameters', () {
      final s = make();
      s.freeze("a");
      s.setFreeValues([30, 20]);
      expect(s["c"], 30);
      expect(s["a"], 1); // frozen, unchanged
      expect(s["b"], 20);
      // Round trip
      s.setFreeValues(s.freeValues());
      expect(s.freeValues(), [30.0, 20.0]);
    });

    test('setFreeValues checks the number of values', () {
      final s = make();
      s.freeze("a");
      expect(() => s.setFreeValues([1]), throwsArgumentError);
      expect(() => s.setFreeValues([1, 2, 3]), throwsArgumentError);
      expect(() => s.setFreeValues([]), throwsArgumentError);
    });

    test('setBounds validates', () {
      final s = make();
      s.setBounds("a", 0, 1);
      expect(s.parameter("a").lower, 0);
      expect(s.parameter("a").upper, 1);
      expect(() => s.setBounds("a", 1, 0), throwsArgumentError);
    });

    test('copy is deep and keeps order, values, state, and bounds', () {
      final s = make();
      s.freeze("a");
      s.setBounds("b", 0, 5);
      final c = s.copy();
      expect(c.names, s.names);
      expect(c.freeValues(), s.freeValues());
      expect(c.parameter("b").upper, 5);
      c["c"] = 99;
      c.thaw("a");
      c.setBounds("b", null, null);
      expect(s["c"], 3);
      expect(s.parameter("a").state, ParameterState.frozen);
      expect(s.parameter("b").upper, 5);
    });

    test('toString', () {
      final s = make();
      s.freeze("a");
      expect(s.toString(), "c = 3.0, a = 1.0 (frozen), b = 2.0");
    });
  });

  group('names', () {
    test('empty names and names with "." throw', () {
      expect(() => Parameter("", 0), throwsArgumentError);
      expect(() => Parameter("a.b", 0), throwsArgumentError);
      expect(() => ParameterSet(["a", ""]), throwsArgumentError);
      expect(() => ParameterSet(["a", "b.c"]), throwsArgumentError);
    });

    test('labels follow the same rules', () {
      final c = ParameterSet(["x"]);
      expect(() => ParameterSet([], children: {"": c}), throwsArgumentError);
      expect(() => ParameterSet([], children: {"g.1": c}), throwsArgumentError);
    });
  });

  group('state', () {
    test('free, frozen, dependent', () {
      final s = ParameterSet(["a", "b"]);
      expect(s.parameter("a").state, ParameterState.free);
      s.freeze("a");
      expect(s.parameter("a").state, ParameterState.frozen);
      s.relate("b", ["a"], (v) => v[0]);
      expect(s.parameter("b").state, ParameterState.dependent);
    });
  });

  group('relations', () {
    ParameterSet abc() {
      final s = ParameterSet(["a", "b", "c"]);
      s.setValues({"a": 1, "b": 2, "c": 3});
      return s;
    }

    test('tie: value follows the source', () {
      final s = abc();
      s.relate("b", ["a"], (v) => v[0]);
      expect(s["b"], 1);
      s["a"] = 7;
      expect(s["b"], 7);
    });

    test('general function of several sources', () {
      final s = abc();
      s.relate("c", ["a", "b"], (v) => 2 * v[0] + v[1]);
      expect(s["c"], 4);
      s["b"] = 10;
      expect(s["c"], 12);
    });

    test('chains are evaluated on read', () {
      final s = abc();
      s.relate("b", ["a"], (v) => v[0] + 1);
      s.relate("c", ["b"], (v) => 2 * v[0]);
      expect(s["c"], 4);
      s["a"] = 5;
      expect(s["c"], 12);
    });

    test('dependent parameters are not free and follow setFreeValues', () {
      final s = abc();
      s.relate("c", ["a"], (v) => 3 * v[0]);
      expect(s.freeNames(), ["a", "b"]);
      s.setFreeValues([2, 5]);
      expect(s["c"], 6);
      expect(s.freeLowerBounds().length, 2);
    });

    test('frozen and dependent sources are allowed', () {
      final s = abc();
      s.freeze("a");
      s.relate("b", ["a"], (v) => v[0]);
      s.relate("c", ["b"], (v) => v[0]);
      expect(s["c"], 1);
    });

    test('cycles throw', () {
      final s = abc();
      expect(() => s.relate("a", ["a"], (v) => v[0]), throwsArgumentError);
      s.relate("b", ["a"], (v) => v[0]);
      s.relate("c", ["b"], (v) => v[0]);
      expect(() => s.relate("a", ["c"], (v) => v[0]), throwsArgumentError);
      expect(s.parameter("a").state, ParameterState.free);
    });

    test('dependent parameters reject value, freeze, thaw, bounds', () {
      final s = abc();
      s.relate("b", ["a"], (v) => v[0]);
      expect(() => s["b"] = 1, throwsArgumentError);
      expect(() => s.freeze("b"), throwsArgumentError);
      expect(() => s.thaw("b"), throwsArgumentError);
      expect(() => s.setBounds("b", 0, 1), throwsArgumentError);
      s.setBounds("b", null, null); // removing bounds is fine
      expect(() => s.relate("b", ["c"], (v) => v[0]), throwsArgumentError,
          reason: "already dependent");
    });

    test('a parameter with bounds cannot become dependent', () {
      final s = abc();
      s.setBounds("b", 0, 5);
      expect(() => s.relate("b", ["a"], (v) => v[0]), throwsArgumentError);
    });

    test('removeRelation: free, keeps the last computed value', () {
      final s = abc();
      s.freeze("b");
      s.relate("b", ["a"], (v) => 10 * v[0]);
      s.removeRelation("b");
      expect(s.parameter("b").state, ParameterState.free);
      expect(s["b"], 10);
      s["a"] = 2;
      expect(s["b"], 10);
      s.removeRelation("b"); // no-op
    });

    test('relation holds references to the source parameters', () {
      final s = abc();
      s.relate("c", ["a", "b"], (v) => v[0] + v[1]);
      final r = s.parameter("c").relation!;
      expect(identical(r.sources[0], s.parameter("a")), isTrue);
      expect(() => r.sources.add(s.parameter("a")), throwsUnsupportedError);
    });

    test('toString shows dependent parameters with description', () {
      final s = ParameterSet(["a", "b"]);
      s["a"] = 1;
      s.relate("b", ["a"], (v) => v[0] + 1, description: "a + 1");
      expect(s.toString(), "a = 1.0, b = 2.0 (dependent: a + 1)");
      s.removeRelation("b");
      s.relate("b", ["a"], (v) => v[0]);
      expect(s.toString(), "a = 1.0, b = 1.0 (dependent)");
    });
  });

  group('setValues', () {
    test('sets several values', () {
      final s = ParameterSet(["a", "b"]);
      s.setValues({"a": 1, "b": 2});
      expect(s["a"], 1);
      expect(s["b"], 2);
    });

    test('unknown or dependent names: nothing changed', () {
      final s = ParameterSet(["a", "b", "c"]);
      s.relate("c", ["a"], (v) => v[0]);
      expect(() => s.setValues({"a": 1, "x": 2}), throwsArgumentError);
      expect(() => s.setValues({"a": 1, "c": 2}), throwsArgumentError);
      expect(s["a"], 0);
    });
  });

  group('bounds of free parameters', () {
    test('in the order of the free parameters', () {
      final s = ParameterSet(["a", "b", "c"]);
      s.setBounds("a", 0, null);
      s.setBounds("b", -1, 1);
      s.setBounds("c", null, 5);
      s.freeze("b");
      expect(s.freeLowerBounds(), [0.0, null]);
      expect(s.freeUpperBounds(), [null, 5.0]);
    });
  });

  group('hierarchy', () {
    ({ParameterSet sum, ParameterSet line, ParameterSet g1}) make() {
      final line = ParameterSet(["a", "b"]);
      final g1 = ParameterSet(["amp", "mu", "sigma"]);
      final sum = ParameterSet(["jitter"], children: {"line": line, "g1": g1});
      return (sum: sum, line: line, g1: g1);
    }

    test('qualified names and order', () {
      final m = make();
      expect(m.sum.names,
          ["jitter", "line.a", "line.b", "g1.amp", "g1.mu", "g1.sigma"]);
      expect(m.sum.labels, ["line", "g1"]);
      expect(m.sum.freeNames(), m.sum.names);
    });

    test('child sets are views, not copies', () {
      final m = make();
      m.g1["mu"] = 3;
      expect(m.sum["g1.mu"], 3);
      m.sum["line.b"] = 2;
      expect(m.line["b"], 2);
      m.sum.freeze("g1.sigma");
      expect(m.g1.parameter("sigma").state, ParameterState.frozen);
      expect(identical(m.sum.child("g1"), m.g1), isTrue);
      expect(identical(m.sum.parameter("g1.mu"), m.g1.parameter("mu")), isTrue);
    });

    test('setFreeValues reaches the child sets', () {
      final m = make();
      m.sum.freeze("jitter");
      m.sum.freeze("g1.amp");
      m.sum.setFreeValues([1, 2, 3, 4]);
      expect(m.line["a"], 1);
      expect(m.line["b"], 2);
      expect(m.g1["mu"], 3);
      expect(m.g1["sigma"], 4);
      expect(m.sum.freeValuesByName(),
          {"line.a": 1.0, "line.b": 2.0, "g1.mu": 3.0, "g1.sigma": 4.0});
    });

    test('nested sets', () {
      final inner = ParameterSet(["x"]);
      final mid = ParameterSet(["y"], children: {"in": inner});
      final outer = ParameterSet([], children: {"mid": mid});
      expect(outer.names, ["mid.y", "mid.in.x"]);
      outer["mid.in.x"] = 5;
      expect(inner["x"], 5);
    });

    test('unknown qualified names throw', () {
      final m = make();
      for (final n in ["g2.mu", "g1.x", "g1", "g1.", ".mu", "mu"]) {
        expect(() => m.sum[n], throwsArgumentError, reason: n);
      }
      expect(() => m.sum.child("x"), throwsArgumentError);
    });

    test('relations across child sets', () {
      final m = make();
      m.sum.relate("g1.sigma", ["line.b"], (v) => 2 * v[0]);
      m.line["b"] = 1.5;
      expect(m.g1["sigma"], 3);
      expect(m.g1.parameter("sigma").state, ParameterState.dependent);
    });

    test('a child set in two composites sees the same state', () {
      final g = ParameterSet(["mu"]);
      final s1 = ParameterSet([], children: {"g": g});
      final s2 = ParameterSet([], children: {"other": g});
      s1["g.mu"] = 4;
      expect(s2["other.mu"], 4);
      s1.freeze("g.mu");
      expect(s2.freeNames(), isEmpty);
    });

    test('the same child set twice throws', () {
      final g = ParameterSet(["mu"]);
      expect(() => ParameterSet([], children: {"a": g, "b": g}),
          throwsArgumentError);
      final mid = ParameterSet([], children: {"g": g});
      expect(() => ParameterSet([], children: {"a": g, "m": mid}),
          throwsArgumentError);
    });

    test('a label equal to an own parameter name throws', () {
      expect(
          () => ParameterSet([
                "jitter"
              ], children: {
                "jitter": ParameterSet(["x"])
              }),
          throwsArgumentError);
    });

    test('toString uses qualified names', () {
      final line = ParameterSet(["a"]);
      final sum = ParameterSet([], children: {"line": line});
      sum.freeze("line.a");
      expect(sum.toString(), "line.a = 0.0 (frozen)");
    });
  });

  group('copy with hierarchy and relations', () {
    test('structure, values, states, and bounds are copied', () {
      final g1 = ParameterSet(["mu", "sigma"]);
      final sum = ParameterSet(["jitter"], children: {"g1": g1});
      sum["g1.mu"] = 2;
      sum.freeze("jitter");
      sum.setBounds("g1.sigma", 0, null);
      final c = sum.copy();
      expect(c.names, sum.names);
      expect(c["g1.mu"], 2);
      expect(c.parameter("jitter").state, ParameterState.frozen);
      expect(c.parameter("g1.sigma").lower, 0);
      // Independent
      c["g1.mu"] = 9;
      expect(g1["mu"], 2);
      expect(identical(c.child("g1"), g1), isFalse);
    });

    test('relations within the set are remapped', () {
      final s = ParameterSet(["a", "b", "c"]);
      s["a"] = 1;
      s.relate("b", ["a"], (v) => 2 * v[0], description: "2 a");
      s.relate("c", ["b"], (v) => v[0] + 1);
      final c = s.copy();
      expect(c["c"], 3);
      c["a"] = 5;
      expect(c["b"], 10);
      expect(c["c"], 11);
      expect(s["b"], 2, reason: "original unchanged");
      expect(identical(c.parameter("b").relation!.sources[0], c.parameter("a")),
          isTrue);
      expect(c.parameter("b").relation!.description, "2 a");
    });

    test('relations across child sets are remapped', () {
      final line = ParameterSet(["b"]);
      final g1 = ParameterSet(["sigma"]);
      final sum = ParameterSet([], children: {"line": line, "g1": g1});
      sum.relate("g1.sigma", ["line.b"], (v) => v[0]);
      final c = sum.copy();
      c["line.b"] = 4;
      expect(c["g1.sigma"], 4);
      expect(g1["sigma"], 0);
    });

    test('sources outside the copied set are still referenced', () {
      final outside = ParameterSet(["x"]);
      final inner = ParameterSet(["y"]);
      // Relation created in a composite, target in the child set
      ParameterSet([], children: {"o": outside, "i": inner})
          .relate("i.y", ["o.x"], (v) => v[0]);
      final c = inner.copy();
      outside["x"] = 7;
      expect(c["y"], 7);
    });
  });
}
