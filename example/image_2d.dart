// Fitting a two-dimensional model: a star on an image.
//
// The data are not x/y pairs but pixel values on a grid. The model is a
// two-dimensional Gaussian on a constant background, defined as a
// `Model<Image>` with its own data type. The objective reuses the
// log-likelihood helper `gaussianLnL` on the flattened pixel values.
//
// Run with: dart run example/image_2d.dart

import 'dart:math';

import 'package:funcfit/funcfit.dart';

/// Pixel values of an image with `width` columns, row by row, and their
/// uncertainties.
class Image {
  Image(this.width, this.values, this.err);

  final int width;
  final List<double> values;
  final List<double> err;

  int get height => values.length ~/ width;
}

/// Two-dimensional Gaussian with center (x0, y0) and widths sx, sy on a
/// constant background.
class Gaussian2D extends Model<Image> {
  Gaussian2D() : super(["background", "amp", "x0", "y0", "sx", "sy"]);

  /// Model values for all pixels, row by row.
  List<double> evaluate(int width, int height) {
    final c = this["background"], amp = this["amp"];
    final x0 = this["x0"], y0 = this["y0"], sx = this["sx"], sy = this["sy"];
    return [
      for (int y = 0; y < height; y++)
        for (int x = 0; x < width; x++)
          c + amp * exp(-0.5 * (pow((x - x0) / sx, 2) + pow((y - y0) / sy, 2)))
    ];
  }

  @override
  double objective(Image image) => -gaussianLnL(
      evaluate(image.width, image.height), image.values, image.err);
}

Future<void> main() async {
  // A 20 x 15 pixel image: star at (8.3, 6.7), widths 1.8 and 1.2 pixels,
  // amplitude 50, background 10, noise with standard deviation 1
  final truth = Gaussian2D()
    ..params.setValues({
      "background": 10, "amp": 50, "x0": 8.3, "y0": 6.7, //
      "sx": 1.8, "sy": 1.2
    });
  const width = 20, height = 15;
  final random = Random(3);
  double normal() =>
      sqrt(-2 * log(1 - random.nextDouble())) *
      cos(2 * pi * random.nextDouble());
  final image = Image(
    width,
    [for (final v in truth.evaluate(width, height)) v + normal()],
    List.filled(width * height, 1.0),
  );

  // Rough start values, e.g., from the brightest pixel
  final star = Gaussian2D()
    ..params.setValues({
      "background": 9, "amp": 40, "x0": 8, "y0": 7, //
      "sx": 1, "sy": 1
    });
  final result = await fit(star, image);
  print(result.converged); // true
  // background 9.93, amp 48.51, x0 8.27, y0 6.69, sx 1.81, sy 1.21
  for (final name in star.params.names) {
    print("$name = ${star[name].toStringAsFixed(2)}");
  }

  // A round star: one width for both directions
  star.relate("sy", ["sx"], (v) => v[0]);
  await fit(star, image);
  print("round: sx = sy = ${star["sx"].toStringAsFixed(2)}"); // 1.48
}
