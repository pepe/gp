
# Simple Counter Example (`gp/events.janet`)
This is the **simplest possible example** showing how to use the core manager
and event modules of the `gp/events` system. It demonstrates how to:

- Define static and dynamic events.
- Use `update`, `effect`, and `watch` event types.
- Compose events together.

---

## 🧠 Goal

To create a simple counter that we can increment and print, using a clean
event-driven architecture.

---

## 📦 Components

### 1. Manager Initialization

```janet
(def manager
  (make-manager @{:counter 0}))
```

The manager starts with state:

```janet
@{:counter 0}
```

---

### 2. Static Event: `IncreaseCounter`

```janet
(define-event IncreaseCounter
  @{:update (fn [_ state] (update state :counter inc))})
```

- This is a **static `update` event**.
- It increments the value of `:counter` by 1.

---

### 3. Static Event: `PrintCounter`

```janet
(define-event PrintCounter
  @{:effect (fn [_ state _]
              (print "Counter is: " (state :counter)))})
```

- This is a **static `effect` event**.
- It prints the value of the counter.

---

### 4. Dynamic Event: `inc-and-print`

```janet
(def inc-and-print
  (make-event @{:watch (fn [_ _ _] [IncreaseCounter PrintCounter])}))
```

- This is a **dynamic `watch` event**.
- It emits both `IncreaseCounter` and `PrintCounter` as child events.
- In effect, it increments and then prints the counter.

---

## ⚙️ Execution Flow

### A. Combine increment and print

```janet
(:transact manager inc-and-print)
```

Output:

```
Counter is: 1
```

### B. Increment ten times

```janet
(:transact manager (seq [_ :range [0 10]] IncreaseCounter))
```

- Emits `IncreaseCounter` 10 times.

### C. Print final value

```janet
(:transact manager PrintCounter)
```

Output:

```
Counter is: 11
```

---

## 🪄 Why It Matters

- **Minimal syntax**: Shows that the system works even with the smallest setup.
- **Clear semantics**: Each event does one thing — update, effect, or watch.
- **Composable logic**: `inc-and-print` combines existing events into a higher-level one.

This pattern is the building block for larger workflows. If this works cleanly,
more complex scenarios will scale smoothly.

