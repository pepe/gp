# Native ML development phases

This file records the stable phase boundary so exploratory implementation does
not silently redefine the project.

## Closed foundations

1. **LLM bootstrap:** local llama.cpp inference remains a working vertical
   client and external oracle.
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
engine validation.

**Kernel-0.1 review gate:** the kernel language boundary is reviewed once,
after the Bayesian vertical. Client pressure accumulates in
[`linalg.md`](linalg.md) until then (`abs` and `max` today; `exp` and
`log` expected from probabilistic clients), and the boundary does not move
before the gate.

## Current phase: Bayesian vertical

Build a small Bayesian client over linalg-0:

1. categorical or naive Bayes updating;
2. linear Gaussian and Kalman filtering;
3. particle filtering with explicit random state and resampling. Random
   numbers are generated host-side from explicit state; neither closed
   foundation provides RNG, and device-side generation is a legitimate
   future client for reopening the kernel-0 boundary, not implicit scope
   of this phase.

Only then should general tensors, automatic differentiation, neural layers,
and native LoRA work begin. Those abstractions will be extracted from working
algorithms rather than assumed in advance.
