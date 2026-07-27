# Native linear algebra

`gp/linalg` is the structured mathematical layer over `gp/compute`. It is
the current construction phase (linalg-0); see
[`development-phases.md`](development-phases.md) for the phase boundary.

The design follows Neanderthal's durable lessons — values carry their
engine, storage is native and zero-copy, matrices carry structure that
algorithms exploit, mutation is explicit — translated into gp's data-first
Janet idiom. A linalg value is a plain struct wrapping a compute-0 view,
and structure dispatch is table-driven by keyword, the same idiom as the
compute capability contract. This is a functional lineage, not an API
compatibility promise.

## Value model

```janet
{:gp/linalg true
 :structure :tr          # :vctr, :ge, :tr, :sy, or :gd
 :view <compute view>    # dense storage; engine and dtype live here
 :uplo :lower            # :tr and :sy only
 :diag :non-unit}        # :tr only, :unit for an implicit unit diagonal
```

| Structure | Meaning | Metadata |
| --- | --- | --- |
| `:vctr` | dense vector | — |
| `:ge` | general dense matrix | — |
| `:tr` | triangular matrix | `:uplo`, `:diag` |
| `:sy` | symmetric matrix | `:uplo` |
| `:gd` | diagonal matrix | — |

Storage is always dense, per the linalg-0 closure decision: structure lives
in metadata that algorithms exploit, never in packed storage layouts, which
would reopen the closed compute-0 view vocabulary.

Reads through `entry` and `to-array` are **logical**, not raw storage
reads: a `:tr` matrix reads zero outside its stored triangle and one on a
`:unit` diagonal, a `:sy` matrix mirrors its stored triangle, and a `:gd`
matrix reads zero off the diagonal. The dense content outside a stored
region is unspecified and never read. Writes through `entry!` must target
stored entries; writing an implicit zero, mirror, or unit diagonal is an
error rather than a silent structure violation.

## Conventions

These bind every subsequent linalg-0 phase:

- **Mutation:** a `!` suffix mutates; the mutated argument is the
  destination and the return value. The destination is the first array
  argument, matching compute-0 (`axpy! y alpha x`, `copy! destination
  source`).
- **Allocation:** pure variants allocate their result on the engine of
  their first array argument.
- **Aliasing:** outputs may alias inputs only where compute-0 already
  guarantees overlap safety (copy, axpy); matrix–vector and matrix–matrix
  destinations must not alias their inputs, validated by storage identity
  where cheap.
- **Result structure:** structure is an input optimization, never inferred
  on outputs. `mv` of anything returns `:vctr`; `mm` returns `:ge` always.
  Inference is how structure metadata becomes wrong.
- **Engines:** a value lives where its storage lives. Nothing transfers
  implicitly; `transfer` is the only movement, inherited from compute-0.
- **Dtypes:** dtype support is the engine's capability contract
  (`compute/capabilities`); linalg adds no dtype policy of its own.
- **Lifecycle:** compute-0 ownership applies unchanged. Values are
  reclaimed by garbage collection or released eagerly through
  `(compute/close (linalg/view value))`; child views retain storage.

## Value layer (phase A)

- Constructors: `vctr`, `ge`, `tr`, `sy`, `gd`. Structured constructors
  take row-major dense values (`gd` takes its diagonal) and validate
  `uplo`/`diag` keywords eagerly.
- Predicates and inspectors: `linalg?`, `vector?`, `matrix?`, `structure`,
  `dtype`, `engine`, `dim`, `mrows`, `ncols`, `uplo`, `unit-diag?`.
- Access: `entry`, `entry!` with the logical-read and stored-write
  semantics above.
- Conversion: `to-array` (logical row-major), `transfer`.
- Zero-copy views: `trans` (flips a `:tr` triangle; `:sy` and `:gd` are
  their own transpose), `row` and `col` on `:ge` only — dense storage rows
  of structured matrices do not represent their logical rows — and
  `subvector`.
- Escape hatch: `view` returns the underlying compute view for interop
  with `gp/compute` and, later, `gp/kernel`.

## Level-1 operations (phase B)

Mutating operations dispatch onto compute-0 with structure validated
first:

- `scal!`, `copy!`, and `axpy!` follow the destination-first convention
  and work on vectors and matrices. `copy!` and `axpy!` require
  structurally identical arguments — same structure keyword, stored
  triangle, and diagonal kind — with shapes, dtypes, and engines validated
  by compute-0 underneath. Nothing converts or transfers implicitly.
- A :unit triangular matrix rejects `scal!` and `axpy!` because its
  implicit diagonal cannot represent the result. This is the "structure is
  never inferred on outputs" convention applied to mutation: an operation
  whose result the structure cannot store is an error, not a silent
  metadata change.
- Structured operations delegate to dense compute-0 kernels over the whole
  storage. This is observationally correct because dense content outside a
  stored region is unspecified and never read; it stays unspecified.

`dot` is defined for vectors and delegates to the engines' native kernels
under the dtype capability contract.

The reductions `sum`, `asum`, `nrm2`, and `amax` are defined for vectors
and return host numbers. They are implemented as synchronous entry reads
and therefore run correctly wherever the storage lives — on OpenCL they
read element-by-element, which is the oracle semantics, not the
performance path. `amax` of an empty vector is 0. The device execution
path for reductions arrives with kernel-0 lowering in a later phase.

## Matrix–vector multiplication (phase C)

`mv!` computes `y = alpha*A*x + beta*y` in place following the
destination-first convention; `mv` returns `A*x` as a fresh `:vctr`
allocated on the engine of `a` — the result-structure convention applied:
structure is never inferred on outputs.

This is where structure metadata starts paying: the `:tr` loop reads only
the stored triangle and adds the implicit unit diagonal, the `:sy` loop
makes one pass over the stored triangle accumulating both the entry and
its mirror, and the `:gd` loop is linear in the dimension. Each structured
variant is tested against the densified `:ge` result.

The contract:

- all three values share one native engine (validated exactly through
  `compute/engine-id`) and one dtype;
- the dtype must be one the engine declares for numerical operations —
  the capability table's `:dot` row is the reference, so integer `mv!`
  works on the C++ oracle and is rejected on OpenCL, and that answer will
  not change when lowering arrives;
- `y` must not share storage with `a` or `x`, validated by storage
  identity per the aliasing convention;
- when `beta` is 0 the previous contents of `y` are never read.

Phase C is the oracle implementation: it computes on the host through
synchronous entry reads wherever the storage lives. The device execution
path arrives with kernel-0 lowering.

## OpenCL lowering (phase D)

linalg is the first real client of kernel-0. When storage lives on an
OpenCL engine, the operations kernel-0 can express execute on the device:

- `sum` and the sum-of-squares inside `nrm2` lower as kernel-0
  reductions for :f32 and :f64 (the square root stays on the host);
- `mv!` and `mv` lower for :ge — including transposed strided views,
  which kernel-0 handles through explicit stride arguments — and :gd;
- `beta` 0 keeps its never-reads-y semantics on the device: the
  destination is zero-filled first, so stale contents (including NaN)
  cannot leak through the `beta * y` term;
- compiled programs are cached exactly per native engine identity and
  kernel through `compute/engine-id` — the primitive compute-0 admitted
  in response to this client, after a per-device cache was caught
  handing one engine a program compiled in another engine's context.

The `asum` and `amax` pressure this phase recorded — kernel-0's closed
arithmetic had no `abs` or `max` — was presented at the kernel-0.1
review gate after the Bayesian vertical and admitted; both reductions
now lower to the device through the admitted functions, discharging the
ledger entry.

Deliberately still on the host path, with the reasons recorded:

- `:tr` and `:sy` matrix–vector kernels wait for a client that needs
  them on device; their host loops remain the oracle.
- Integer reductions stay on host reads (their entry semantics are
  already exact), and integer `mv!` on OpenCL remains excluded by the
  capability contract, unchanged from phase C.

Device results are validated against the host oracle in the acceptance
suite — exactly for integer-valued data, within tolerance for
accumulation-order-sensitive float data.

## Matrix multiplication (phase E)

`mm` returns `A*B` as a fresh `:ge` on the operands' engine, dispatching
to the engines' native compute-0 matrix multiplication on both backends
— including transposed strided operands, which the native kernels
handle. Structured operands are logically densified first (implicit
zeros, mirror, and unit diagonals materialize), so every structure
multiplies correctly today, while structure-exploiting multiplication
(`trmm`/`symm`-style) waits for a client that needs it. There is no
`mm!`: nothing native computes into an existing destination, and no
client has asked for one.

This completes linalg-0. Its contract is closed in the same sense as
compute-0 and kernel-0: Windows-verified, Linux acceptance pending as a
portability qualification, and new features admitted only in response to
clients above it.

## Linalg-1: factorization, opened by the Kalman client

The Kalman gain in `gp/bayes` demanded a solve, formally opening
linalg-1 with exactly two admissions and nothing more:

- `cholesky` factors a symmetric positive-definite matrix into its
  lower `:tr` factor, reading the logical lower triangle on the host;
  a non-positive pivot is an error, which is also how Gaussians
  discover they have degenerated.
- `solve` runs forward or back substitution over a `:tr` matrix,
  honoring the stored triangle and implicit `:unit` diagonals; zero
  diagonals are singular and error.

Both are host oracles in the phase-C sense — float dtypes only, exact
against textbook factors in the acceptance suite, device paths waiting
for a client that needs them.

## Beyond linalg-0

Waiting for clients, in the order pressure is expected:

- kernel-0.1 candidates (`abs`, `max`, expected `exp`/`log`) accumulate
  for the review gate recorded in
  [`development-phases.md`](development-phases.md);
- `mm!`, structure-exploiting `mm`, device `:tr`/`:sy` matrix–vector
  kernels, and `dia`/`submatrix` views wait for concrete callers;
- an elementwise vector product (Hadamard) is demanded by `gp/bayes`
  categorical updating, which computes it on the host today — the first
  linalg-0 pressure item.

Deliberately outside linalg-0:

- `dia` and `submatrix` zero-copy views need strided forms beyond the
  closed compute-0 vocabulary and wait for a concrete client;
- factorizations and solvers are linalg-1 work. Forewarning, in the same
  spirit as the RNG note in the phase plan: the Kalman filter in the
  Bayesian phase will demand a solve or Cholesky, and that demand — not
  BLAS/LAPACK completeness — is what should open linalg-1.
