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

Compute-0 and kernel-0 are now infrastructure contracts. New features should
be admitted only in response to a client above them. Canonical status: the
contracts are closed; Linux acceptance is a pending portability
qualification, and portability fixes must preserve these semantics.

Admitted under this rule so far: `compute/engine-id`, identity inspection
in the class of `storage-id`, demanded by `gp/linalg` kernel caching and
engine validation.

**Kernel-0.1 review gate:** the kernel language boundary is reviewed once,
after the Bayesian vertical. Client pressure accumulates in
[`linalg.md`](linalg.md) until then (`abs` and `max` today; `exp` and
`log` expected from probabilistic clients), and the boundary does not move
before the gate.

## Current phase: linalg-0

The next construction target is `gp/linalg`, beginning with mathematical
structure rather than additional kernel machinery:

1. define vector and matrix protocols over compute views;
2. preserve general, transposed, diagonal, triangular, and symmetric
   structure where algorithms can exploit it — represented as dense compute-0
   storage plus linalg-level structure metadata; packed and banded storage
   layouts are out of linalg-0 scope because they would reopen the closed
   compute-0 view vocabulary;
3. implement selected level-1 operations and matrix-vector multiplication
   against the C++ oracle;
4. lower the same operations to OpenCL through kernel-0;
5. establish allocation, mutation, alias, and result-shape conventions;
6. add matrix multiplication without claiming BLAS/LAPACK completeness.

## Following vertical proof

After linalg-0, build a small Bayesian client:

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
