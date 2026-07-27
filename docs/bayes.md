# Bayesian computation

`gp/bayes` is the Bayesian vertical over `gp/linalg` — the client whose
demands shape the layers beneath it, per
[`development-phases.md`](development-phases.md). It follows Bayadera's
role in the Uncomplicate lineage without promising its API: probability
values are plain data over linalg storage, updating is explicit, and
nothing is sampled or approximated silently.

## Value model

A categorical distribution is a struct: a tuple of distinct support
labels and a linalg `:vctr` of probabilities (`:f32` or `:f64`) on an
explicit engine. Constructors accept non-negative *weights* and
normalize at construction — Bayes updates produce unnormalized mass, so
normalization is the operation you always want, and zero total mass is
always an error rather than a NaN.

A naive Bayes model is a categorical class prior plus, per feature, a
support tuple and a linalg `:ge` matrix holding one conditional
distribution per class row (rows normalize at construction).

## Phase 1 — categorical updating and naive Bayes

- `categorical`, `categorical?`, `support`, `probabilities`,
  `probability` — construction and inspection.
- `update` — pointwise prior-times-likelihood with renormalization; an
  observation impossible under every label is an error.
- `naive-bayes`, `naive-bayes?`, `classes`, `posterior` — evidence
  accumulates in log space with log-sum-exp normalization, so long
  products of tiny likelihoods do not underflow. Unobserved features
  are absent from the observation dictionary; unknown features or
  values are errors.

Sequential updates compose: updating on two observations equals one
update with the product likelihood, and the acceptance suite pins this.

## Recorded pressure from phase 1

Per the phase discipline, wants are recorded, not smuggled in:

- **linalg:** categorical updating computes an elementwise vector
  product on the host; a Hadamard-product operation is the first
  linalg-0 client pressure item.
- **kernel-0.1 gate:** `posterior` calls `math/log` and `math/exp` on
  the host per class and observed feature. These are the expected
  probabilistic call sites for `exp`/`log` at the kernel review gate.
- **gp/bayes itself:** the todo-prediction client
  ([`examples/todo-prediction.janet`](../examples/todo-prediction.janet))
  demanded a top-k accessor on categorical distributions; `top` was
  admitted in phase 2a on that evidence.

## Phase 2a — the discrete Bayes filter

- `top` returns up to k support labels, most probable first — admitted
  on the todo-prediction client's demand.
- `transition` constructs a stochastic matrix over a support: one
  conditional weight row per source label, normalized at construction
  into a linalg matrix, zero-mass rows rejected.
- `predict` pushes a belief through the dynamics — the transition
  matrix transposed and multiplied against the belief vector through
  `linalg/mv`, which lowers to the device on OpenCL engines. `predict`
  is the motion half of a discrete Bayes filter and `update` the
  evidence half; a filter step is deliberately their composition,
  `(update (predict belief dynamics) likelihoods)`, not a fused
  operation.

The acceptance suite pins the Russell–Norvig umbrella world to its
exact textbook posteriors (9/11 after one observation, 621/703 after
two) and the dynamics invariants: identity preserves belief,
permutations permute it, uniform rows erase it.

**Measured on the todo data**
([`examples/todo-filter.janet`](../examples/todo-filter.janet)): tag
dynamics from consecutive pairs plus creation-hour evidence score 25%
top-1 / 61% top-3 on the 132 held-out todos — statistically tied with
the naive Bayes variants (27/64 hour+previous, 29/65 hour-only)
against the 15/68 static baseline. The recorded conclusion: at 657
todos over 28 tags, sequence structure adds no measurable lift over
time-of-day alone; the ceiling is the data, not the machinery. The
filter is validated and waiting for richer data, not tuning.

## Phase 2b — linear Gaussian and Kalman filtering

A multivariate Gaussian is a linalg mean vector plus a `:sy`
covariance; positive definiteness is not checked at construction but
discovered through Cholesky when the update needs it. `linear-dynamics`
(`x' = F x + w`) and `observation` (`z = H x + v`) carry their matrices
as linalg values with `:sy` noise.

The filter reuses the same two verbs by dispatching on the belief:
`predict` of a Gaussian is the Kalman prediction `mean' = F mean`,
`P' = F P Fᵀ + Q`; `update` of a Gaussian takes an observation model
and a measurement and runs the Kalman measurement update. The gain is
never formed from an inverse: it solves through the Cholesky factor of
the innovation covariance and two triangular substitutions — the
demand that opened linalg-1. The posterior covariance is rebuilt as
`:sy` from its lower triangle, which keeps it symmetric by
construction.

The acceptance suite pins the scalar filter to exact fractions (mean
8/7, variance 3/7 after two textbook steps), rotation dynamics rotate
the mean and preserve isotropic covariance, sharp evidence pins the
mean and collapses the variance while the posterior stays positive
definite, and every dispatch mismatch errors.

## Deferred phases

- **Particle filtering** — explicit random state through Janet's
  seedable `math/rng`, host-side per the phase plan; systematic
  resampling; log-space weights. Device RNG remains a future
  kernel-boundary client, not this phase's scope. It closes the
  evidence file for the kernel-0.1 review gate.
