(import gp/llm)

(def model-path
  (or (os/getenv "GP_LLM_MODEL")
      (error "set GP_LLM_MODEL to a local decoder-only GGUF file")))
(def input (or (os/getenv "GP_LLM_PROMPT") "Once upon a time"))

(def model (llm/load-model model-path))
(def context (llm/session model :context-size 512))

# generate-stream is an ordinary iterable fiber: consume it with `each`, pause
# between pieces, or compose it with Janet's other iterable operations.
(each piece (llm/generate-stream context input :max-tokens 80)
  (prin piece)
  (flush))
(print)
