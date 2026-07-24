# Native compute

`gp/compute` is gp's common native numerical substrate. It deliberately begins
below tensors and linear algebra: engines own storage, views describe storage,
and operations preserve those ownership and layout facts.

Two engines currently implement the contract:

- `gp/compute/cpp` is the synchronous, portable reference engine;
- `gp/compute/opencl` discovers system OpenCL devices and executes kernels on
  explicitly selected devices.

## Capability contract

`compute/capabilities` returns the immutable, per-engine compute-0 contract.
It records the backend and device, available dtypes and views, dtype support
for synchronous and queued operations, and execution properties:

```janet
(def contract (compute/capabilities cpu))
(contract :contract)                         # => :compute-0
(get-in contract [:synchronous :dot])        # => (:f32 :f64 :i32)
(compute/supports? cpu :dot :f64)            # => true
(compute/supports? cpu :dot :f64 :queued)    # => true
```

OpenCL capabilities belong to a selected engine, not merely to the OpenCL
backend in general. In particular, `:f64` appears only when that device
supports it. Integer storage, transfer, fill, and copy are supported on
OpenCL, while BLAS-like integer operations remain excluded because their
overflow semantics do not yet match the C++ oracle.

The capability table is descriptive rather than a dispatch registry. Public
operations still validate their arguments and return useful Janet errors.
The acceptance suite sweeps every declared operation, dtype, and execution
mode against both engines, so the table cannot silently drift from native
behavior. Engines outside the closed backend set are rejected rather than
described, and the contract is computed once per engine handle and cached.

## Values and ownership

A view records:

- its engine;
- dtype (`:f32`, `:f64`, or `:i32`);
- logical shape;
- element strides;
- offset into retained storage.

`slice`, `row`, and `transpose` create zero-copy views. Every view retains its
storage, and storage retains its engine. Consequently a child remains usable
after its parent view or original engine handle is closed.

`close`, `close-engine`, `close-queue`, and `close-event` provide deterministic,
idempotent release. Janet garbage collection is the fallback.

## Engines and explicit transfer

```janet
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)

(def cpu (cpp/engine))
(def gpu (opencl/engine :platform 0 :device 0))

(def host (compute/vector cpu :f32 [1 2 3]))
(def device (compute/transfer gpu host))
(def back (compute/transfer cpu device))
```

`transfer` is the only operation that moves values between engines. `copy!`,
`axpy!`, `dot`, and `mm` reject operands from different engines. There is no
implicit host/device transfer.

`opencl/platforms` returns nested platform and device descriptions;
`opencl/devices` returns the devices as a flat array. `opencl/available?`
allows programs and tests to make OpenCL optional.

The OpenCL loader is resolved dynamically at runtime. Building gp needs the
pinned Khronos headers but does not require a vendor SDK or OpenCL import
library. Running the OpenCL engine requires a system OpenCL ICD and device
driver.

## Operations

The synchronous surface is common to both engines:

- construction: `alloc`, `from-array`, `vector`, `matrix`;
- inspection: `engine`, `dtype`, `rank`, `shape`, `strides`, `count`;
- views: `slice`, `row`, `transpose`;
- mutation: `put!`, `fill!`, `copy!`, `scal!`, `axpy!`;
- results: `get`, `to-array`, `dot`, `mm`.

Overlapping `copy!` and `axpy!` read a stable logical source. The C++ engine
also makes failing integer operations atomic.

OpenCL currently executes floating-point `scal!`, `axpy!`, `dot`, and `mm`.
`:i32` supports allocation, transfer, indexed access, `fill!`, and `copy!`;
integer BLAS-like OpenCL operations are intentionally rejected until their
overflow semantics can match the reference engine.

## Queues and events

Synchronous operations use an engine's internal queue. Explicit queues expose
dataflow without changing the convenient API:

```janet
(def queue (compute/queue gpu))
(def x (compute/vector gpu :f32 [1 2 3]))
(def y (compute/alloc gpu :f32 [3]))

(def initialized (compute/enqueue-fill! queue x 7))
(def copied (compute/enqueue-copy! queue y x initialized))
(def scaled (compute/enqueue-scal! queue y 0.5 copied))
(def [magnitude ready]
  (compute/enqueue-dot queue y y scaled))

(compute/wait ready)
(compute/to-array magnitude) # => @[36.75]
```

Dependencies are explicit event arguments. OpenCL commands remain asynchronous
until `wait` or `finish`; C++ events complete immediately. Events, queues,
views, and engines retain the native resources needed by outstanding work.

The queued surface is:

- mutation: `enqueue-fill!`, `enqueue-copy!`, `enqueue-scal!`,
  `enqueue-axpy!`;
- results: `enqueue-dot`, `enqueue-mm`.

Mutating submissions return an event. Result-producing submissions return
`[result event]`. The dot result is a one-element view, not an immediate host
number. This keeps it owned by the selected engine and avoids an implicit
device-to-host transfer. Wait for its event before reading it on the host or
use the event as a dependency for later queued work.

Dependencies can cross queues when all queues, events, and views belong to the
same engine. Queued `copy!` and `axpy!` preserve stable-source semantics even
when source and destination views overlap.

## Numerical role

The C++ engine is the semantic oracle. OpenCL tests run the same view,
transfer, overlap, dot-product, and matrix-multiplication cases against actual
device kernels. This layer is intended to support structured `gp/linalg`,
probabilistic computation, Bayesian filters, tensors, and neural networks—not
to force all of those structures to become tensors.

Raw device-program compilation is intentionally absent from the public
`gp/compute` API. By convention only `gp/kernel` uses the native engine
bridge directly; it owns
the source language, compiler metadata, launch validation, and compiled-kernel
lifecycle. This keeps compute-0 a numerical substrate rather than a compiler
framework.
