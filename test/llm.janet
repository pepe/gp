(use spork/test jhydro)
(import gp/llm)

(start-suite "LLM documentation")
(assert-docs "gp/llm")
(end-suite)

(start-suite "LLM boundary")
(assert-error "missing model" (llm/load-model "this-model-does-not-exist.gguf"))
(assert-error "model path type" (llm/load-model 42))
(end-suite)

# A real model is deliberately not part of the repository. Point this variable
# at any decoder-only GGUF to enable the integration checks. llama.cpp's own
# 1.19 MB stories260K fixture is a convenient choice; see the README.
(when-let [model-path (os/getenv "GP_LLM_TEST_MODEL")]
  (start-suite "LLM GGUF integration")

  (def model (llm/load-model model-path))
  (def info (llm/model-info model))
  (assert (string? (info :description)) "model description")
  (assert (> (info :size) 0) "model size")
  (assert (> (info :parameters) 0) "parameter count")
  (assert (> (info :context-size) 0) "training context")

  (def text "Once upon a time")
  (def tokens (llm/tokenize model text))
  (assert (> (length tokens) 0) "tokenize")
  (assert (= text (llm/detokenize model tokens)) "token round trip")
  (assert (= "" (llm/detokenize model @[])) "empty detokenization")

  (def context (llm/session model :context-size 128 :threads 1))
  (assert (>= (llm/session-context-size context) 128) "session context")
  (assert-error "non-positive output" (llm/generate context text :max-tokens 0))
  (assert-error "invalid top-p" (llm/generate context text :top-p 1.1))
  (assert-error "context overflow"
                (llm/generate context (string/repeat text 100) :max-tokens 8))
  (def first-output
    (llm/generate context "Once upon a time" :max-tokens 12 :temperature 0))
  (def second-output
    (llm/generate context "Once upon a time" :max-tokens 12 :temperature 0))
  (assert (= first-output second-output)
          (string "greedy generation is deterministic and reusable: "
                  (describe first-output) " != " (describe second-output)))
  (assert (> (length first-output) 0) "generated text")

  (var stream
    (llm/generate-stream context "Once upon a time" :max-tokens 8 :temperature 0))
  (assert (= :fiber (type stream)) "stream is an iterable fiber")
  (def streamed (string/join (seq [piece :in stream] piece)))
  (assert (> (length streamed) 0) "streamed text")

  # Collecting an old, completed generation must not unlock a newer one.
  (var active
    (llm/generate-stream context "Once upon a time" :max-tokens 8 :temperature 0))
  (def first-key (next active))
  (assert (string? (in active first-key)) "active stream yielded text")
  (set stream nil)
  (gccollect)
  (assert-error "one active generation per session"
                (llm/generate context text :max-tokens 1 :temperature 0))
  (set active nil)
  (gccollect)
  (assert (> (length (llm/generate context text :max-tokens 1 :temperature 0)) 0)
          "abandoned stream releases session during collection")

  (llm/reset context)
  (gccollect)
  (end-suite))
