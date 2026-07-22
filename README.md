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
