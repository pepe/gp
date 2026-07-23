# Native ML foundation for gp and TWM

## The most basic goal

Make **typed, shaped, owned native numerical storage** a first-class Janet
value, and execute a small set of operations on it through interchangeable
C++ and OpenCL engines.

That is the first foundation. It is deliberately smaller than a tensor
framework, a linear-algebra library, or a machine-learning library. Those
systems can be built on it without inheriting the representation or lifecycle
of any one native dependency.

In one diagram:

```text
Janet values and protocols
          |
          v
storage + view + engine + queue/event
          |
          +------------------+
          |                  |
          v                  v
    C++ reference         OpenCL
       engine              engine
```

The C++ engine establishes semantics and provides a portable fallback. The
OpenCL engine establishes device execution, explicit transfer, queues, and
asynchrony. CUDA is not required by the architecture.

## Why storage comes before tensors

A tensor combines several different concerns:

- allocation and ownership;
- element type;
- dimensions, strides, and offset;
- mathematical structure;
- execution device;
- operations and differentiation.

The foundation should keep these concerns separable. The same storage may be
viewed as a vector, matrix, tensor, batch of particles, probability table, or
model parameter block. A symmetric matrix, sparse matrix, distribution, and
Bayesian state should preserve their own structure rather than pretend to be
generic dense tensors.

Tensors will be important clients of the foundation, not its ontology.

## Initial concepts

### Engine

An engine owns the implementation of operations and describes their
capabilities. The first engines are:

- `gp/compute/cpp`: portable CPU reference implementation;
- `gp/compute/opencl`: OpenCL platforms and devices.

Application code depends on the common compute protocol rather than either
engine's native handles.

### Storage

Storage owns a contiguous native allocation:

- engine and device;
- element type;
- capacity in elements and bytes;
- native handle;
- lifetime state.

Storage has deterministic, idempotent release as well as a Janet garbage
collector fallback. A view retains its storage, so collecting a parent value
cannot invalidate a live child view.

### View

A view describes storage without owning another allocation:

- dtype;
- shape;
- strides;
- element offset;
- optional mathematical structure.

Slicing, transposition, row/column views, and reshaping are zero-copy whenever
the requested layout permits it. Layout is described by strides; the
foundation does not globally decree row-major or column-major storage.

### Queue and event

Work is submitted to a queue and may produce an event.

- C++ operations may complete immediately and return an already-complete event.
- OpenCL operations may remain asynchronous.
- Dependencies are explicit rather than hidden behind accidental global
  synchronization.

The first public API may offer convenient synchronous operations, but the
native boundary must not make asynchronous execution impossible.

### Dtype

The first milestone needs only a disciplined subset:

- `:f32`;
- `:f64`;
- `:i32`.

Additional integer, half-precision, complex, Boolean, and quantized types
should be added in response to concrete algorithms. Dtype conversion is always
explicit.

## Semantic invariants

1. **Janet owns the public semantics.** Native libraries are engines, not the
   public object model.
2. **No implicit device transfer.** Moving data between host and OpenCL storage
   is visible in the program.
3. **Views do not copy silently.** An allocating conversion has a distinct
   operation.
4. **Mutation is named.** Allocating operations have ordinary names; operations
   that overwrite storage use `!`.
5. **Ownership is unambiguous.** Release is idempotent, views retain storage,
   and garbage collection is a safety net.
6. **The C++ engine is the oracle.** OpenCL results are compared with it within
   dtype-appropriate tolerances.
7. **Structure is preserved.** Special matrices and probabilistic objects may
   expose structure-specific protocols and algorithms.
8. **Errors cross the boundary as Janet errors.** Native error codes and build
   logs are not the user-facing API.
9. **Determinism is controllable.** Random operations receive explicit random
   state; deterministic reference tests remain possible.
10. **Backends are replaceable.** No public value contains a required ggml,
    BLAS, OpenCL, or vendor-specific type.

## Illustrative Janet surface

The names are provisional, but the ownership and execution relationships are
intentional:

```janet
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)

(def host (cpp/engine))
(def gpu (opencl/engine :device 0))

(def x (compute/vector host :f32 [1 2 3]))
(def y (compute/vector host :f32 [10 20 30]))

(compute/dot x y)                    # 140
(def gx (compute/transfer gpu x))    # explicit copy
(def gy (compute/transfer gpu y))
(compute/dot gx gy)

(def a (compute/matrix host :f32 [2 3] [1 2 3 4 5 6]))
(def row (compute/slice a 0))        # retained zero-copy view
(compute/fill! row 0)
```

Eventually scoped resource ownership may look like:

```janet
(compute/with-arena [arena host]
  (def a (compute/matrix arena :f32 [1000 1000]))
  (def b (compute/matrix arena :f32 [1000 1000]))
  (compute/mm a b))
```

The exact macro should be chosen only after the native value lifecycle is
tested in ordinary Janet code and fibers.

## First buildable milestone: compute-0

`compute-0` is complete when both C++ and OpenCL engines provide:

- engine and device discovery;
- allocation and release;
- construction from Janet numbers;
- transfer to and from Janet arrays/buffers;
- explicit C++/OpenCL transfer;
- shape, stride, dtype, and size inspection;
- zero-copy one-dimensional slices;
- `fill!`, `copy!`, `scal!`, `axpy!`, `dot`, and matrix multiplication;
- queue completion and explicit waiting;
- useful errors for dtype, shape, engine, and lifetime mismatches.

Acceptance requires:

- matching C++ and OpenCL results within stated tolerances;
- allocation/release stress tests with garbage collection;
- tests proving that views retain storage;
- tests proving that slices share storage;
- tests proving that transfers never happen implicitly;
- Windows and Linux builds, with other platforms added as available.

This milestone is enough to build meaningful numerical work without claiming
to be Neanderthal or a tensor framework.

## Relationship to the Uncomplicate ecosystem

This is a functional lineage and scope map, not an API compatibility promise.

| Uncomplicate project | Its role | Planned gp counterpart | When |
| --- | --- | --- | --- |
| Commons and ClojureCPP | Native resources, memory, and C++ substrate | `gp/compute` and `gp/compute/cpp` | Foundation |
| ClojureCL | OpenCL platforms, devices, queues, buffers, and kernels | `gp/compute/opencl` | Foundation |
| Neanderthal | Structured vectors/matrices and BLAS/LAPACK linear algebra | `gp/linalg` over compute engines | After compute-0 |
| Bayadera | Bayesian computation and accelerated inference | `gp/prob` and `gp/filter` | Early vertical client |
| Deep Diamond | Tensors, neural networks, and deep learning | `gp/tensor`, `gp/autodiff`, and `gp/nn` | Later |
| Fluokitten | Generic functional composition over supported structures | Janet iteration/protocol integration, possibly `gp/fold` | Grows with clients |
| Diamond ONNX Runtime | Model interchange and external execution | `gp/model` interchange and optional runtime engines | Later |
| ClojureCUDA | NVIDIA-specific accelerator substrate | No initial counterpart | Optional future work |

The most immediate replacement target is therefore **not Neanderthal as a
whole**. It is the common native substrate represented by Commons,
ClojureCPP, and ClojureCL, plus the lowest storage/engine layer on which a
Neanderthal-like linear algebra API can later stand.

Neanderthal's important design lessons include pluggable engines, native
zero-copy storage, structured matrices, explicit mutating operations, and a
small language-shaped layer over established numerical kernels. See
[Neanderthal](https://neanderthal.uncomplicate.org/) and its
[native computation guide](https://neanderthal.uncomplicate.org/articles/tutorial_native.html).
The wider ecosystem and the complementary roles of Deep Diamond and Bayadera
are summarized in the
[Uncomplicate ecosystem plan](https://dragan.rocks/articles/25/Clojure-AI-ML-high-performance-Uncomplicate).

## First client beyond linear algebra

The first non-neural client should be a small Bayesian filter. This prevents
the compute layer from accidentally adopting assumptions that only suit neural
networks.

A useful sequence is:

1. categorical/naive Bayes updating on the C++ engine;
2. the same likelihood calculations on OpenCL;
3. a linear Gaussian/Kalman filter using `gp/linalg`;
4. a particle filter exercising random state, resampling, queues, and
   reductions.

This establishes that a model may carry belief, uncertainty, observation, and
temporal state—not merely parameters and gradients.

## Relationship to gp/llm and the Python bootstrap

`gp/llm` remains a living vertical application. Initially it may continue to
use llama.cpp directly, while Python PEFT supplies training. Neither dependency
defines the future compute API.

They serve as:

- working tools for TWM now;
- reference implementations and numerical oracles;
- sources of real requirements;
- interchange partners for GGUF and adapter artifacts.

Native Janet components should replace borrowed machinery incrementally when
the required semantics are understood and tests exist.

## Explicit non-goals of the foundation

The first milestone does not attempt:

- automatic differentiation;
- general tensors or broadcasting;
- neural-network layers;
- model training;
- BLAS/LAPACK completeness;
- sparse computation;
- distributed execution;
- implicit graph compilation;
- CUDA;
- transparent use of every available accelerator.

Those are future clients and extensions. Keeping them outside `compute-0`
makes the first foundation small enough to finish and strong enough to trust.

## Construction order

1. Preserve the current `gp/llm` work as its own reviewable commit.
2. Specify the C ABI for engine, storage, view, queue, and event handles.
3. Implement and test the C++ reference engine.
4. Implement the same minimal operation set with OpenCL.
5. Add `gp/linalg` structures and selected BLAS-level operations.
6. Build the first Bayesian client.
7. Extract tensor and autodiff abstractions from actual neural requirements.
8. Use LoRA training and a reconstructed small language model as demanding
   vertical proofs.

The framework grows outward from working algorithms while keeping Janet—not a
foreign runtime—as the place where its concepts acquire meaning.
