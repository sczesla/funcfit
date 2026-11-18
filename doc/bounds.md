# Bounds: avoid them where possible

Bounds (`setBounds`) keep a parameter within a range; the fit never leaves
it. They are, however, hard edges in the parameter space, and these can
make fitting harder:

- A result exactly on a bound may not be a regular estimate: the data may
  prefer a value beyond the bound, or the search got stuck there.
  Statistics that assume an optimum inside the range (e.g., uncertainties
  from the curvature of the objective) do not apply in their usual form.
- A parameter on a bound such as `amplitude >= 0` can make other
  parameters meaningless. For example, for a sine curve with an amplitude
  of 0, period and phase no longer affect the model. Their values are
  arbitrary, and the search may stop at such a point.

Some methods to avoid bounds:

- **Post-processing of equivalent solutions:** For instance, fit the
  phase `phi` of a sine freely and reduce it afterward, `phi % (2 * pi)`
  (or `phi % 1` if the phase is given in cycles).
- **Reparameterization:** For example, fit a positive parameter via its
  logarithm (the model uses `exp(lnSigma)`). Write a sine as
  `a * sin(2 * pi * x / per) + b * cos(2 * pi * x / per)`, which is linear
  in `a` and `b` and has no sign ambiguity. Fitting a frequency instead of
  a period can avoid the division by zero.

Keep bounds for values where the model is undefined or impossible and no
convenient reparameterization exists. If a result lands on a bound, check
whether the bound is necessary, fit again without it or from other start
values, and compare the objectives.
