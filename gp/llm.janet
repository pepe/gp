(import ./llm-native :as native)

(defn load-model
  "Load a local GGUF model."
  [path &named mmap]
  (default mmap true)
  (native/load-model path mmap))

(defn model-info
  "Return basic metadata for a loaded model."
  [model]
  {:description (native/model-description model)
   :size (native/model-size model)
   :parameters (native/model-parameters model)
   :context-size (native/model-context-size model)})

(defn tokenize
  "Convert UTF-8 text to model token IDs."
  [model text &named add-special]
  (default add-special false)
  (native/tokenize model text add-special))

(defn detokenize
  "Convert model token IDs to UTF-8 text."
  [model tokens &named remove-special]
  (default remove-special false)
  (native/detokenize model tokens remove-special))

(defn session
  "Create a mutable inference session for `model`."
  [model &named context-size batch-size threads]
  (default context-size 2048)
  (default batch-size (min context-size 512))
  (default threads 0)
  (when (<= context-size 0) (error "context-size must be positive"))
  (when (<= batch-size 0) (error "batch-size must be positive"))
  (when (< threads 0) (error "threads must not be negative"))
  (native/new-session model context-size batch-size threads))

(defn reset
  "Clear the inference memory in an idle session."
  [context]
  (native/reset context))

(defn session-context-size
  "Return the actual context capacity of a session."
  [context]
  (native/session-context-size context))

(defn- start
  [session input options]
  (def config
    (merge
      {:max-tokens 128
       :temperature 0.8
       :top-k 40
       :top-p 0.95
       :min-p 0.05
       :seed 0xFFFFFFFF}
      options))
  (when (<= (config :max-tokens) 0) (error "max-tokens must be positive"))
  (when (< (config :temperature) 0) (error "temperature must not be negative"))
  (when (< (config :top-k) 0) (error "top-k must not be negative"))
  (when (or (< (config :top-p) 0) (> (config :top-p) 1))
    (error "top-p must be between 0 and 1"))
  (when (or (< (config :min-p) 0) (> (config :min-p) 1))
    (error "min-p must be between 0 and 1"))
  (when (or (< (config :seed) 0) (> (config :seed) 0xFFFFFFFF))
    (error "seed must be between 0 and 4294967295"))
  (native/start-generation session input
                           (config :max-tokens)
                           (config :temperature)
                           (config :top-k)
                           (config :top-p)
                           (config :min-p)
                           (config :seed)))

(defn generate-stream
  ```
  Return an iterable fiber that yields generated UTF-8 text pieces. Options
  include `:max-tokens`, `:temperature`, `:top-k`, `:top-p`, `:min-p`, and `:seed`.
  ```
  [session input &named max-tokens temperature top-k top-p min-p seed]
  (def options @{})
  (each [key value] [[:max-tokens max-tokens]
                     [:temperature temperature]
                     [:top-k top-k]
                     [:top-p top-p]
                     [:min-p min-p]
                     [:seed seed]]
    (when (not (nil? value)) (put options key value)))
  (coro
    (def generation (start session input options))
    (while true
      (def [has-piece? piece] (native/generation-step generation))
      (if has-piece?
        (yield piece)
        (break)))))

(defn generate
  "Generate text synchronously and return it as a string."
  [session input &named max-tokens temperature top-k top-p min-p seed]
  (def output @"")
  (each piece (generate-stream session input
                               :max-tokens max-tokens
                               :temperature temperature
                               :top-k top-k
                               :top-p top-p
                               :min-p min-p
                               :seed seed)
    (buffer/push output piece))
  (string output))
