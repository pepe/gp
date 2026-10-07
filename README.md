# gp = Good Place compacted

[![builds.sr.ht status](https://builds.sr.ht/~pepe/gp.svg)](https://builds.sr.ht/~pepe/gp)
[![GitHub Actions](https://github.com/pepe/gp/actions/workflows/test.yml/badge.svg)](https://github.com/pepe/gp/actions/workflows/test.yml)

Good Place was a loose set of Janet libraries of mine. As `spork` grew bigger
and more varied, and after talking the problem through with paulsnar, I
compacted them into one library, with more consistent names for its modules
and functions.

gp is at 0.x, and its API still moves between minor versions. If you depend
on it, pin a release tag.

Development happens at [git.sr.ht/~pepe/gp](https://git.sr.ht/~pepe/gp).
[github.com/pepe/gp](https://github.com/pepe/gp) is a mirror, with issues and
pull requests turned off; send patches and reports to <pe@pan.earth>.

## Requirements

- Janet. CI builds Janet's master branch: v1.40.1 hangs in
  `test/events.janet`, and `.build.yml` says why.
- `spork` and `jhydro`, which `janet-pm deps` installs.
- A C compiler and a C++17 compiler: MSVC on Windows, GCC or Clang
  elsewhere.
- Optionally, an OpenCL driver. The OpenCL runtime is loaded dynamically, so
  no vendor SDK is needed to build; without a driver only the C++ engine is
  available.

## Installing

The Khronos OpenCL headers come in as a Git submodule, so clone recursively:

```sh
git clone --recursive https://git.sr.ht/~pepe/gp
cd gp
janet-pm deps
janet-pm install
```

In an existing clone, `git submodule update --init --recursive` fetches them.

## Modules

| Module | What it does |
| --- | --- |
| `gp/events` | Reactive events managed over channels: updates, watches, effects, and producers |
| `gp/route` | Routing: route templates compiled to PEGs, lookup, and resolving back to paths |
| `gp/datetime` | Working with dates and times |
| `gp/utils` | Utilities that were not merged from marble to spork |
| `gp/atomic` | Atomic file writes |
| `gp/qr` | QR code generation with scalable SVG output |
| `gp/data` | Storing, schemas, and navigating data; see [Data](#data) |
| `gp/net` | Network servers; see [Net](#net) |
| `gp/compute` | Typed native storage, retained views, and numerical operations |
| `gp/kernel` | Linted Janet kernel definitions and normalized numerical IR |
| `gp/linalg` | Structured linear algebra over `gp/compute` |
| `gp/bayes` | Bayesian computation over `gp/linalg` |
| `gp/environment` | Application runtime: `app`, `base`, `thicket`, `sentry`, and `static-web` |
| `gp/gen` | Project generator, run by the `gpgen` script |

Native modules, built from `cjanet/` and `src/`:

- `gp/codec` - base64, md5, and sha* coding.
- `gp/data/fuzzy` - fuzzy scorer, its algorithm taken from fzy.
- `gp/net/curi` - URI parsing and escaping.
- `gp/ownership` - process-scoped store ownership.
- `gp/qr-native` - the QR encoder.
- `gp/compute/native` - the C++ reference engine and the OpenCL backend.

### Data

- `store` - simple table based store with marshaling and optional identity index.
- `schema` - validation and analysis based on data and functions.
- `navigation` - path based navigation through hierarchical data structures.
- `magic` - traversal functions from literal paths.
- `fuzzy` and `scorer` - fuzzy search on strings.
- `intel` - business intelligence. Alpha quality.
- `charts` - charting to SVG. Alpha quality.

### Net

- `server` - general network serving, based on a supervisor channel, on a
  TCP `host:port` or a Unix socket `unix:/absolute/path`.
- `socket` - Unix socket listeners claimed by one process, their stale
  paths recovered and removed again when they close. POSIX only.
- `http` - all the affordances for serving HTTP.
- `ws` - all the affordances for serving websockets.
- `rpc` - all the affordances for serving RPC.
- `uri` - URI parsing and escaping.

### Static websites

`gpgen` creates a static-site project from a recipe:

```sh
gpgen new gp/gen/static-web site.jdn
```

The configuration file must provide at least a project `name`; see
`examples/gen/static-web.jdn`. The generated site uses
`gp/environment/static-web`, renders MDZ content to `public`, and builds
with `janet <project-name> prod` once its dependencies are installed.

### Native compute

`gp/compute` has C++17 reference and OpenCL engines. Its native views have
explicit dtype, shape, strides, engine, and ref-counted storage; slices, rows,
and transposes are zero-copy, and transfers between engines are always
explicit.

```janet
(import gp/compute)
(import gp/compute/cpp)

(def cpu (cpp/engine))
(def a (compute/matrix cpu :f32 [2 3] [1 2 3 4 5 6]))
(def b (compute/matrix cpu :f32 [3 2] [7 8 9 10 11 12]))

(compute/to-array (compute/mm a b))
# => @[58 64 139 154]
```

`gp/kernel` is the staged language between the mathematical APIs and the
engines. `defkernel` expands typed Janet forms into immutable, source-mapped
IR, which the C++ evaluator interprets as the semantic oracle and which lowers
to OpenCL C:

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

`gp/linalg` wraps compute views with structure: general, triangular,
symmetric, and diagonal. `gp/bayes` builds categorical distributions, Bayes
updating, naive Bayes, and discrete, Kalman, and particle filters on top:

```janet
(import gp/bayes)

(def weather (bayes/categorical cpu :f64 [:sunny :rainy] [1 1]))
(def after-clouds (bayes/update weather [0.3 0.8]))
(bayes/probability after-clouds :rainy)   # => 8/11
```

The contracts of each layer are in [`docs/`](docs): [compute](docs/compute.md),
[kernel](docs/kernel.md), [linalg](docs/linalg.md), and
[bayes](docs/bayes.md). [Native ML foundation](docs/native-ml-foundation.md)
describes the plan, and [development phases](docs/development-phases.md)
where it stands.

### QR codes

```janet
(import gp/qr)

(def code (qr/encode "https://example.org")) # defaults to :medium ECC
(qr/size code)                               # logical module-field size
(qr/module code 3 7)                         # query a logical module
(qr/svg code)                                # htmlgen structure with quiet zone
```

`qr/encode` supports `:low`, `:medium`, `:quartile`, and `:high` error
correction. `qr/svg` adds the standard four-module quiet zone and returns an
`htmlgen` structure rather than serialized SVG.

## Examples

With gp installed, run an example from the repository root:

```sh
janet examples/data/navigation.janet
```

## Development

Work in a local Janet tree, which git ignores as `dev`:

```sh
janet-pm env dev
. dev/bin/activate      # dev\bin\activate.ps1 in PowerShell
janet-pm deps
janet-pm install
janet-pm test
```

Tests import the installed gp, so run `janet-pm install` after every change
before testing. A single file runs with `janet test/http.janet`.
`janet bin/test.janet` watches `gp`, `cjanet`, and `test`, and installs and
tests again on every change.

CI runs on [builds.sr.ht](https://builds.sr.ht/~pepe/gp) under Alpine, and on
GitHub Actions under Linux, macOS, and Windows.

## License

MIT; see [LICENSE](LICENSE).

gp includes code from others, under their own licenses:

- Project Nayuki's [QR Code generator](https://github.com/nayuki/QR-Code-generator),
  MIT, at revision `2c9044de6b049ca25cb3cd1649ed7e27aa055138`; see
  `src/qrcodegen.LICENSE`.
- Kazuho Oku's [picohash](https://github.com/kazuho/picohash), public domain,
  in `src/picohash.h`.
- The URI parser in `gp/net/uri.janet` and `cjanet/curi.janet` comes from
  [andrewchambers/janet-uri](https://github.com/andrewchambers/janet-uri).
- The fuzzy scorer follows [fzy](https://github.com/jhawthorn/fzy).
- The Khronos [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers),
  Apache-2.0, as the `vendor/OpenCL-Headers` submodule at release
  `v2026.05.29`.
