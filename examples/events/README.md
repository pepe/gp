
# Event Examples Overview

This directory contains several example applications demonstrating how to use
the `gp/events` system in different scenarios — from minimal counter updates to
fully interactive CLI applications.

Each example has its own detailed walkthrough in a separate README.

---

## 🧮 Counter

🔗 [Source](/~pepe/gp/tree/master/item/examples/events/counter/init.janet)  
📄 [Description](/~pepe/gp/tree/master/item/examples/counter/README.md)

A minimal example showing the essence of event composition.

### Flow:

1. Initialize a manager with `:counter = 0`.
2. Confirm a combined event `inc-and-print`:
   - Emits `IncreaseCounter` (increment state).
   - Emits `PrintCounter` (print state).
3. Confirm `IncreaseCounter` 10× and print again.

### Run:

```sh
janet examples/events/counter/init.janet
```

---

## 🔗 Chains

🔗 [Source](/~pepe/gp/tree/master/item/examples/events/chains/init.janet)  
📄 [Description](/~pepe/gp/tree/master/item/examples/chains/README.md)

Demonstrates multi-step event chaining based on file inputs.

### Flow:

1. Initialize manager with `:directory-file`.
2. Confirm `ReadDirectory`:
   - Reads `dir.txt` with PEG.
   - Emits `save-directory` to update state.
   - Emits `ProcessDirectory`, which emits `get-user` per line.
     - Each `get-user` reads a user file and emits `save-user`.
3. Confirm `PrintUsers` to output results.

### Run:

```sh
janet examples/events/chains/init.janet
```

---

## 💻 Prompt CLI App

🔗 [Source](/~pepe/gp/tree/master/item/examples/prompt/)  
📄 [Description](/~pepe/gp/tree/master/item/examples/prompt/README.md)

A full-featured prompt-driven CLI showcasing dynamic parsing, producers, and thread orchestration.

### Modules:

- `init.janet`: Entry point and event dispatch.
- `parser.janet`: PEG grammar parser for user commands.
- `events.janet`: All event definitions and state logic.

### Highlights:

- `AddRandom`: static producer simulating synchronous heavy computation.
- `add-many-randoms`: emits multiple `AddRandom` events.
- `ThreadRandom`: static threaded computation event.
- `add-many-trandoms`: thread-based batch emitter.
- `unknown-command`: dynamic event with both `:watch` and `:effect`.

### Flow:

1. Forever loop:
   - Read user input
   - Parse input into event
   - Confirm event via manager

### Run:

```sh
janet examples/events/prompt/init.janet
```

Type `h` in the prompt for available commands.

---
