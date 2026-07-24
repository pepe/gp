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

## Deferred beyond the value layer

Planned linalg-0 phases build on this layer in order: level-1 operations
against the C++ oracle, structure-exploiting matrix–vector multiplication,
OpenCL lowering through kernel-0, and matrix multiplication dispatching to
the native compute-0 kernels.

Deliberately outside linalg-0:

- `dia` and `submatrix` zero-copy views need strided forms beyond the
  closed compute-0 vocabulary and wait for a concrete client;
- factorizations and solvers are linalg-1 work. Forewarning, in the same
  spirit as the RNG note in the phase plan: the Kalman filter in the
  Bayesian phase will demand a solve or Cholesky, and that demand — not
  BLAS/LAPACK completeness — is what should open linalg-1.
