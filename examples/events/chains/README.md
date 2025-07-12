
# Event Chaining Example (`gp/events.janet`)

This example demonstrates **event chaining** using the `gp/events` system. It
reads a directory file listing user names, loads user descriptions from separate
text files, updates internal state, and finally prints the collected data. This
illustrates both static and dynamic event composition.

---

## 🧠 Goal

To read a list of users from a file, load each user’s description from a
matching text file, and store it in application state for later output.

---

## 📦 Components

### 1. Initial Manager Setup

```janet
(def- manager
  (make-manager @{:directory-file ..., :users @{}}))
```

The manager holds:

- `:directory-file` – path to the file listing users.
- `:users` – a table to accumulate user data.

---

### 2. `save-user`

```janet
(defn save-user [user description] ...)
```

- A **dynamic `update`** event that stores a user's description into state.

---

### 3. `get-user`

```janet
(defn get-user [user] ...)
```

- A **dynamic `watch`** event:
  - Reads the user's text file.
  - Returns a `save-user` event with the content.

---

### 4. `save-directory`

```janet
(defn save-directory [dir] ...)
```

- A **dynamic `update`** that stores the list of usernames into the state under `:directory`.

---

### 5. `ProcessDirectory`

```janet
(define-watch ProcessDirectory ...)
```

- A **static `watch`**:
  - Iterates over all users in `:directory`
  - Emits `get-user` for each one

---

### 6. `ReadDirectory`

```janet
(define-watch ReadDirectory ...)
```

- A **static `watch`**:
  - Parses `dir.txt` with PEG.
  - Emits:
    1. `save-directory` event
    2. `ProcessDirectory` event

---

### 7. `PrintUsers`

```janet
(define-effect PrintUsers ...)
```

- A **static `effect`**:
  - Loops through `:users`
  - Prints each user's description

---

## ⚙️ Execution Flow

```janet
(:transact manager ReadDirectory)
```

1. Reads and parses the directory file.
2. Stores the user list in state.
3. Triggers a set of `get-user` events.
4. Each `get-user` reads a file and emits `save-user`.

```janet
(:transact manager PrintUsers)
```

- Prints the final accumulated state.

---

## 🪄 Why It Works

- **Dynamic event chaining**: `get-user` emits another event at runtime.
- **State-driven logic**: `ProcessDirectory` reacts to current state.
- **Composable pipeline**: everything is an event — no callbacks or mutation outside event logic.

---

## 🧪 Extensions

- Add error handling for missing files.
- Convert printing to JSON output.
- Integrate with a web interface for real-time display.

---

This example highlights the core design of the system: declarative, functional,
and chainable event computation.

