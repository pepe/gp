# gp = Good Place compacted

Good Place was loose set of some of libraries of mine. But as I saw `spork`
getting bigger and more varied, and as I talked thru this problem with
paulsnar, I decided to compact them into one with all the functionality.

This also brings more concisious naming of modules and API functions.

I hope you like it.

## Modules

### Data

This module contains all the parts for scheming, storing, and navigating data
in your application.

- `store` - simple table based store with marshaling and optional identity index.
- `schema` - validation and analysis based on data and functions.
- `navigation` - path based navigation through hierarchical data structures.

### Serve - TDB

- `process` - reactive event management with channels.
- `server` - general network serving part based on supervisor channel.
- `routing` - general routing library.
- `http` - all the affordances for serving http.
- `ws` - all the affordances for serving websockets.
- `rpc` - all the affordances for serving RPC

### Utils - TBD
- `datetime` - working with time.
- `remote` - working with remotes.
- `gen` - generating new things.
