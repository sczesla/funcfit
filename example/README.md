# Examples

Each example is a complete program that generates its own data. Run one
with `dart run example/<file>.dart`.

| Example | What it shows |
|---|---|
| [funcfit_example.dart](funcfit_example.dart) | Fitting a straight line: free and frozen parameters, Gaussian and Laplace noise |
| [sample_distribution.dart](sample_distribution.dart) | A model that is not a curve: estimating mean and standard deviation of a normal distribution from a sample (`Model<List<double>>`) |
| [image_2d.dart](image_2d.dart) | Two-dimensional data: fitting a star on an image (`Model` with its own data type), then relating both widths |
| [line_with_jitter.dart](line_with_jitter.dart) | Extending `CurveModel` with a fitted noise term (jitter) by overriding `lnL` |
| [doublet.dart](doublet.dart) | Combining models (`CurveSum`) and tying parameters with relations: two lines with known separation and equal width |
| [stepwise_and_starts.dart](stepwise_and_starts.dart) | Fitting step by step (freeze, fit, thaw, fit) and keeping the best of several start values |
| [progress_and_cancel.dart](progress_and_cancel.dart) | Following the progress with `onIteration` and cancelling a running minimization |
