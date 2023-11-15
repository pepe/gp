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

### Data

This module contains all the parts for scheming, storing, and navigating data
in your application.

- `store` - simple table based store with marshaling and optional identity index.
- `schema` - validation and analysis based on data and functions.
- `navigation` - path based navigation through hierarchical data structures.
- `fuzzy` - simple fuzzy search on strings. Algo stolen from fzy.

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

### Gen
- `project` - simple project generator

#### TBD
- `static` - static web generator
- `app` - network application

### - TBD

- move all the examples in. And some more.
- more documentation.
