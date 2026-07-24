# Native kernel language

`gp/kernel` is the small, Janet-native compiler frontend between mathematical
operations and compute engines. It follows CJanet's staged pattern:

```text
Janet forms -> normalized IR -> validation -> backend lowering
```

The first checkpoint intentionally stops before backend lowering. Kernels can
be defined, linted, inspected, and evaluated synchronously against the C++
reference engine. OpenCL source generation and asynchronous launch will be
added only after these semantics are stable.

## Definition

```janet
(import gp/kernel)

(kernel/defkernel saxpy
  [n:i32
   alpha:f32
   (x (buffer :f32 [n] :read))
   (y (buffer :f32 [n] :read-write))]

  (parallel [i 0 n]
    (store! y [i]
      (+ (* alpha (load x [i]))
         (load y [i])))))
```

Scalar parameters use CJanet-style `name:dtype` bindings. Buffers use
`(name (buffer dtype shape access))`. The initial dtypes are `:f32`, `:f64`,
and `:i32`; access is `:read`, `:write`, or `:read-write`.

Initial statements are `parallel`, `serial`, and `store!`. Expressions are
scalar references, constants, `load`, arithmetic, and `reduce`.

## Linting and safety

`defkernel` participates in Janet flychecking and reports diagnostics with
`maclintf`. The normalized value also retains diagnostics and source
locations, so correctness does not depend on a particular lint threshold.

`kernel/valid?` must be true before evaluation or eventual compilation.
Strict diagnostics include invalid bindings, unbound names, illegal buffer
access, rank errors, malformed reductions, and unsafe parallel indexing.

Kernel-0 deliberately applies a strong parallel rule: stores must use exactly
the surrounding parallel indexes. Loads from a `:read-write` buffer must use
those same indexes. This admits deterministic elementwise kernels while
rejecting accidental cross-work-item races. Read-only inputs may use other
indexes, which will later allow matrix multiplication and stencil-like reads.

Loop and reduction indexes cannot shadow parameters or enclosing indexes.
Arithmetic over statically incompatible dtypes is rejected. During reference
evaluation, writable buffers may not alias another argument's storage; later
versions may relax this only through an explicit, provable alias contract.

Flychecking performs no native compilation and launches no work.

## Inspection

Kernel definitions are immutable Janet data:

```janet
(kernel/name saxpy)
(kernel/parameters saxpy)
(kernel/ir saxpy)
(kernel/diagnostics saxpy)
(kernel/valid? saxpy)
```

The IR is normalized rather than executable Janet syntax. Backend compilers
will consume this same representation, and generated source will remain
available for inspection.

## Reference evaluation

```janet
(import gp/compute)
(import gp/compute/cpp)

(def engine (cpp/engine))
(def x (compute/vector engine :f32 [1 2 3]))
(def y (compute/vector engine :f32 [10 20 30]))

(kernel/run! saxpy {:n 3 :alpha 2 :x x :y y})
(compute/to-array y) # => @[12 24 36]
```

`run!` is a synchronous semantic evaluator. It requires C++-engine views,
checks scalar values, dtypes, shapes, access declarations, and indexes, then
returns the original bindings after mutation.

It is not the performance implementation. Its purpose is to be the oracle
against which generated C++ and OpenCL kernels will be tested.

## Next lowering checkpoint

The next checkpoint will introduce compiled-kernel ownership, OpenCL C source
generation, device compilation and cache keys, followed by launches through
the existing compute queues and events. Scheduling remains separate from
kernel meaning.
