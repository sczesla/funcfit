// Runs all example programs, so that none of them can go stale unnoticed.

import 'package:test/test.dart';

import '../example/doublet.dart' as doublet;
import '../example/image_2d.dart' as image_2d;
import '../example/line_with_jitter.dart' as line_with_jitter;
import '../example/progress_and_cancel.dart' as progress_and_cancel;
import '../example/sample_distribution.dart' as sample_distribution;
import '../example/stepwise_and_starts.dart' as stepwise_and_starts;

void main() {
  final examples = <String, Future<void> Function()>{
    'sample_distribution': sample_distribution.main,
    'image_2d': image_2d.main,
    'line_with_jitter': line_with_jitter.main,
    'doublet': doublet.main,
    'stepwise_and_starts': stepwise_and_starts.main,
    'progress_and_cancel': progress_and_cancel.main,
  };
  examples.forEach((name, run) {
    test('example $name runs', run);
  });
}
