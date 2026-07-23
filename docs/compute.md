# Native compute

`gp/compute` is gp's common native numerical substrate. It deliberately begins
below tensors and linear algebra: engines own storage, views describe storage,
and operations preserve those ownership and layout facts.

Two engines currently implement the contract:

- `gp/compute/cpp` is the synchronous, portable reference engine;
- `gp/compute/opencl` discovers system OpenCL devices and executes kernels on
  explicitly selected devices.

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
