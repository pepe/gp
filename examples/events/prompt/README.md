
# CLI Event-Driven Example (`gp/events.janet`)

This example demonstrates a complete command-line application built using
the `gp/events` system. It integrates PEG grammar parsing, dynamic and static
events, and producers. The app maintains a state and responds to
user commands like `+5`, `-3`, `r 10`, etc., by updating state and performing
computations.

---

## 🧠 Summary

This CLI app lets users:

- Add or subtract values to a counter.
- Reset the counter.
- Add results of random computations.
- View current state.
- Exit the program.

---

## 📦 Components

### 1. PEG Grammar

```janet
(def grammar ...)
(defn parse-command [s] ...)
```

Defines commands like:

- `+ [num]` – increment
- `- [num]` – decrement
- `0` – reset
- `r [num]` – random adds
- `p` – print state
- `q` – quit
- `h` – help

---

### 2. State Initialization

```janet
(define-watch PrepareState ...)
```

Sets up initial state:

- `:amount` set to `0`
- Then incremented by `1`

---

### 3. Updates

```janet
ZeroAmount
increase-amount
decrease-amount
```

Modify `:amount` by 0, +N, or -N.

---

### 4. Computation with Producers

#### `AddRandom`

- Synchronous computation loop of random values.
- Produces `increase-amount`.

#### Batching

```janet
add-many-randoms
```

Generate multiple events in sequence.

---

### 5. Effects & Feedback

```janet
PrintState
PrintHelp
Exit
unknown-command
```

Print messages or exit app.

---

### 6. Main Loop — `Prompt` Producer

```janet
(define-watch Prompt ...)
```

- Repeatedly reads user input.
- Parses command.
- Emits appropriate event using `produce`.

---

## ⚙️ Flow

```janet
(:transact manager PrepareState Prompt)
(:await manager)
```

1. Sets up initial state.
2. Starts prompt loop.
3. Waits for manager to run.

---

## 🪄 Why It Works Well

- Functional purity: clear state transformation.
- Event roles are strict: update vs watch vs effect.
- Dynamic event construction.
- Safe concurrency via `producer`.

---

## 🧪 Possible Extensions

- File-based logging
- Undo/redo via state snapshots
- Timed events
- UI frontend binding (REPL, web, etc.)

---

Designed and driven with the elegance of event-based architecture. This example
could be the foundation for CLI tooling, scripting systems, or educational
sandbox environments.

