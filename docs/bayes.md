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

## Deferred phases

- **Linear Gaussian and Kalman filtering** — opens linalg-1 with
  exactly the factorization the Kalman gain demands (Cholesky and
  triangular solve on the C++ oracle).
- **Particle filtering** — explicit random state through Janet's
  seedable `math/rng`, host-side per the phase plan; systematic
  resampling; log-space weights. Device RNG remains a future
  kernel-boundary client, not this phase's scope.
