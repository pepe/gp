# Native kernel language

`gp/kernel` is the small, Janet-native compiler frontend between mathematical
operations and compute engines. It follows CJanet's staged pattern:

```text
Janet forms -> normalized IR -> validation -> backend lowering
```

Kernels can be defined, linted, inspected, evaluated synchronously against the
C++ reference engine, or lowered into OpenCL C and launched asynchronously.
The reference evaluator and device compiler consume the same IR.

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
consume this same representation. `kernel/opencl-source` returns deterministic
OpenCL C without compiling or touching a device.

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
against which generated OpenCL kernels are tested.

## OpenCL compilation and launch

```janet
(import gp/compute/opencl)

(def engine (opencl/engine))
(def queue (compute/queue engine))
(def x (compute/vector engine :f32 [1 2 3]))
(def y (compute/vector engine :f32 [10 20 30]))
(def compiled (kernel/compile engine saxpy))

(def event
  (kernel/launch compiled queue
    {:n 3 :alpha 2 :x x :y y}))
(compute/wait event)
```

`compile` returns immutable metadata containing the definition, entry name,
device name, generated source, deterministic `kernel/cache-key`, launch
domains, and an owned native program. `kernel/source` exposes the exact code
sent to the driver. OpenCL build logs are included in compilation errors.

Buffer ABI arguments are a memory object, element offset, and one element
stride per logical axis. Slices and transposed views therefore remain
zero-copy. Scalars retain their declared dtype. Up to three nested parallel
axes map to `get_global_id`; serial loops and reductions remain local control
flow within a work item.

`launch` repeats runtime dtype, shape, alias, and engine validation. It accepts
dependency events after the bindings and returns a compute event. Empty
parallel domains produce an already-complete event after their dependencies.
The compiled kernel, queues, views, and events independently retain their
engine. `kernel/close` provides eager release; garbage collection is the
fallback.

Launch geometry must be host-computable from scalar parameters and arithmetic.
All parallel statements at the same nesting depth must have identical bounds.
These restrictions keep scheduling explicit and prevent generated kernels
from silently choosing incompatible global sizes.

## Current boundary

Kernel-0 compiles OpenCL only; C++ remains the semantic oracle rather than a
second code-generation target. There is deliberately no opaque binary cache
yet. The stable key identifies compiler version, device, and source, while
the OpenCL driver may use its own program cache. A gp-managed binary cache can
be added later without changing kernel meaning or launch ABI.
