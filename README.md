# gp = Good Place compacted

Good Place was loose set of some of libraries of mine. But as I saw `spork`
getting bigger and more varied, and as I talked thru this problem with
paulsnar, I decided to compact them into one with all the functionality.

This also brings more concisious naming of modules and API functions.

I hope you do not use it just now, as too much is happening.

## Modules

- `events` - reactive events management with channels.
- `route` - general routing library.
- `datetime` - working with time.
- `utils` - what was not merged from marble to spork. Utils.
- `tui` - higher level terminal UI
- `qr` - QR-code generation and scalable SVG output.
- `llm` - local GGUF inference and fiber-based token streaming.
- `compute` - typed native storage, retained views, and numerical operations.
- `kernel` - linted Janet kernel definitions and normalized numerical IR.

The planned native numerical and machine-learning substrate is described in
[`docs/native-ml-foundation.md`](docs/native-ml-foundation.md).

### Native compute

`gp/compute` begins the native ML foundation with C++17 reference and OpenCL
engines. Its native views have explicit dtype, shape, strides, engine, and
ref-counted storage. Vector slices, matrix rows, and transpose are zero-copy;
each child retains its storage independently.

```janet
(import gp/compute)
(import gp/compute/cpp)

(def cpu (cpp/engine))
(def a (compute/matrix cpu :f32 [2 3] [1 2 3 4 5 6]))
(def b (compute/matrix cpu :f32 [3 2] [7 8 9 10 11 12]))

(compute/to-array (compute/mm a b))
# => @[58 64 139 154]
```

The initial dtypes are `:f32`, `:f64`, and `:i32`. Operations include
`fill!`, overlap-safe `copy!`, `scal!`, overlap-safe `axpy!`, `dot`, and `mm`.
Explicit `close` is available for deterministic release, with garbage
collection as the fallback. Transfers between C++ and OpenCL engines are
always explicit. OpenCL discovery, device kernels, command queues, dependency
events, and asynchronous fill/copy are included.

See [`docs/compute.md`](docs/compute.md) for the API, ownership model, backend
capabilities, and queue example.

### Native kernels

`gp/kernel` is the staged language between mathematical APIs and compute
engines. `defkernel` expands typed Janet forms into immutable, source-mapped
IR, participates in Janet flychecking, and rejects unsafe access, dtype, shape,
shadowing, and parallel-index patterns before backend compilation.

The C++ evaluator is the semantic oracle; the same IR now lowers to
inspectable OpenCL C and launches through retained queues and events:

```janet
(kernel/defkernel scale
  [n:i32 alpha:f32
   (x (buffer :f32 [n] :read-write))]
  (parallel [i 0 n]
    (store! x [i] (* alpha (load x [i])))))

(def compiled (kernel/compile opencl-engine scale))
(def event
  (kernel/launch compiled queue {:n 1024 :alpha 0.5 :x device-x}))
```

See [`docs/kernel.md`](docs/kernel.md) for the grammar, safety boundary,
generated-source API, ownership model, and launch contract.

Kernel-0 is now closed as infrastructure. The current construction phase is
`gp/linalg`; see [`docs/development-phases.md`](docs/development-phases.md).

### Linear algebra

`gp/linalg` is the structured mathematical layer under construction over
`gp/compute` (phase linalg-0), following Neanderthal's lineage in gp's
data-first Janet idiom. The value layer wraps compute views in dense
storage plus structure metadata — general, triangular, symmetric, and
diagonal — with logical reads, structure-validated writes, and zero-copy
transpose, row, column, and subvector views:

```janet
(import gp/linalg)

(def a (linalg/ge cpu :f32 2 3 [1 2 3 4 5 6]))
(def t (linalg/tr cpu :f32 2 [1 0 2 3]))   ; :lower :non-unit by default
(linalg/entry t 0 1)                        ; => 0, implicit zero
(linalg/to-array (linalg/col a 1))          ; zero-copy column view
(linalg/transfer gpu a)                     ; explicit, like compute-0
```

Level-1 operations follow destination-first mutation: `scal!`, `copy!`,
and `axpy!` validate structure before dispatching to the engines, `dot`
runs on native kernels under the dtype capability contract, and the
reductions `sum`, `asum`, `nrm2`, and `amax` read logical entries as the
oracle semantics on any engine.

See [`docs/linalg.md`](docs/linalg.md) for the value model and the
conventions that bind the coming operation phases.

### QR codes

`gp/qr` exposes a minimal QR API:

```janet
(import gp/qr)

(def code (qr/encode "https://example.org")) ; defaults to :medium ECC
(qr/size code)                              ; logical module-field size
(qr/module code 3 7)                        ; query a logical module
(qr/svg code)                               ; htmlgen structure with quiet zone
```

`qr/encode` supports `:low`, `:medium`, `:quartile`, and `:high` error
correction. `qr/svg` adds the standard four-module quiet zone around the
logical module field and returns an `htmlgen` structure rather than serialized
SVG.

The encoder vendors Project Nayuki's MIT-licensed C QR Code generator at
revision `2c9044de6b049ca25cb3cd1649ed7e27aa055138`; see
`src/qrcodegen.LICENSE` for attribution.

### Local LLM inference

`gp/llm` is a small CPU-only Janet interface to a pinned `llama.cpp`. It loads
local decoder-only GGUF models, exposes tokenization, and supports both ordinary
and streaming generation. Streaming is represented by an iterable Janet fiber.

```janet
(import gp/llm)

(def model (llm/load-model "model.gguf"))
(def context (llm/session model :context-size 2048))

(print (llm/generate context "Once upon a time" :max-tokens 64))

(each piece (llm/generate-stream context "The answer is" :max-tokens 64)
  (prin piece)
  (flush))
```

Generation options are `:max-tokens`, `:temperature`, `:top-k`, `:top-p`,
`:min-p`, and `:seed`. A session handles one active generation at a time and is
reused after a stream is exhausted. Chat templates, embeddings, accelerators,
and model downloads are intentionally outside this first API.

The build requires CMake and a C++17 compiler. After cloning, initialize the
dependencies before installing:

```sh
git submodule update --init --recursive
jpm install
```

For real-model integration tests, set `GP_LLM_TEST_MODEL` to a local GGUF.
llama.cpp's own small fixture is useful for this:

```sh
curl -L -o stories260K.gguf \
  https://huggingface.co/ggml-org/tiny-llamas/resolve/main/stories260K.gguf
GP_LLM_TEST_MODEL=stories260K.gguf jpm test
```

`llama.cpp` is included as a Git submodule at revision
`6d5a910c503df242457b2e83f4918d422c0a68ab` and retains its MIT license in
`vendor/llama.cpp/LICENSE`.

Khronos OpenCL-Headers are included as a Git submodule at release
`v2026.05.29`, revision
`6fe718c31a45fe25151362a72ef041c3a1047cbd`, and retain their Apache-2.0
license in `vendor/OpenCL-Headers/LICENSE`. The OpenCL runtime is loaded
dynamically, so a vendor SDK is not required; OpenCL use requires a system ICD
and device driver.

### Data

This module contains all the parts for scheming, storing, and navigating data
in your application.

- `store` - simple table based store with marshaling and optional identity index.
- `schema` - validation and analysis based on data and functions.
- `navigation` - path based navigation through hierarchical data structures.
- `fuzzy` - simple fuzzy search on strings. Algo stolen from fzy.

#### Alpha Quality

- `intel` - business inteligence
- `charts` - charting to svg

### Net

All the tools for building network servers.

- `server` - general network serving part based on supervisor channel.
- `http` - all the affordances for serving http.
- `ws` - all the affordances for serving websockets.
- `rpc` - all the affordances for serving RPC

### Native

- `fuzzy` - fuzzy find scorer, algorythm stolen from fzy.
- `curi` - uri parser/escaper.
- `codec` - base64, md5, sha* coding.
- `term` - termbox2 wrapper

## Examples

To run examples you need to install `spork` dependency first:

```janet
> jpm deps
```¨

Then you must install the library itself:

```janet
> jpm install
```

Then you should be able to run a the examples with simple:

```janet
> janet examples/data/navigation.janet
```

### - TBD

- move all the examples in. And some more.
- more documentation.
