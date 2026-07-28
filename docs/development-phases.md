# Native ML development phases

This file records the stable phase boundary so exploratory implementation does
not silently redefine the project.

## Closed foundations

1. **LLM bootstrap:** local llama.cpp inference served as the first vertical
   client and external oracle, and has done its work. It has been removed
   from gp: a language-model runtime is not part of a numerical library, and
   vendoring one made every consumer of gp build it. If it returns it will
   be its own library. The lessons it taught — that the compute API must not
   be shaped around one runtime — are kept below.
2. **Compute-0:** typed owned storage, retained strided views, C++ and OpenCL
   engines, explicit transfer, synchronous operations, queues, and events.
3. **Kernel-0:** linted Janet IR, C++ reference evaluation, deterministic
   OpenCL C, native compilation, and dependency-aware launch.
4. **Linalg-0:** structured values (dense storage plus metadata for
   general, triangular, symmetric, and diagonal shapes) over compute
   views, logical reads with structure-validated writes, level-1
   operations, structure-exploiting matrix–vector multiplication, OpenCL
   lowering through kernel-0, and matrix multiplication on the native
   engines. Conventions and contract in [`linalg.md`](linalg.md).
   Packed and banded storage stayed out, as decided; factorizations open
   linalg-1 only on client demand.

These are now infrastructure contracts. New features should be admitted
only in response to a client above them. Canonical status: the contracts
are closed; Linux acceptance is a pending portability qualification, and
portability fixes must preserve these semantics.

Admitted under this rule so far: `compute/engine-id`, identity inspection
in the class of `storage-id`, demanded by `gp/linalg` kernel caching and
engine validation; and linalg-1 (`cholesky` and triangular `solve` as
C++ oracles), opened by the Kalman gain in `gp/bayes`.

**Kernel-0.1 review gate — executed.** The gate was held after the
Bayesian vertical completed, as scheduled. The full ledger — `abs` and
`max` from linalg reductions, `exp` and `log` from probabilistic
evidence — was admitted as a float-only math-function class pinned to
OpenCL builtin semantics (see [`kernel.md`](kernel.md)), and the
clients that filed the pressure were discharged onto the device in the
same review. The kernel boundary is closed again; it moves only at a
future gate with a newly accumulated ledger.

## Completed vertical: bayes-0

The Bayesian vertical is complete, in order: categorical and naive
Bayes updating; the discrete Bayes filter; linear Gaussian and Kalman
filtering (which opened linalg-1); particle filtering with explicit
random state through Janet's `math/rng` and systematic resampling.
Contract in [`bayes.md`](bayes.md). Device RNG remains a legitimate
future kernel-boundary client, not retroactive scope.

## Next

The construction target after the gate is deliberately unchosen. General
tensors, automatic differentiation, neural layers, and native LoRA
remain the horizon; those abstractions will be extracted from working
algorithms — the next real client decides which, not this document.
