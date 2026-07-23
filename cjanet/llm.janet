(use spork/cjanet)

(include <janet.h>)
(include <llm-helper.h>)

(typedef Model (named-struct Model native (* GpLlmModel)))
(typedef Session (named-struct Session native (* GpLlmSession) model (* Model)))
(typedef Generation (named-struct Generation native (* GpLlmGeneration) session (* Session)))

(function gc-model :static [p:*void size:size_t] -> int
  (def model:*Model p)
  (when model->native (gp-llm-model-free model->native))
  (return 0))

(function gc-session :static [p:*void size:size_t] -> int
  (def session:*Session p)
  (when session->native (gp-llm-session-free session->native))
  (return 0))

(function mark-session :static [p:*void size:size_t] -> int
  (def session:*Session p)
  (when session->model (janet-mark (janet-wrap-abstract session->model)))
  (return 0))

(function gc-generation :static [p:*void size:size_t] -> int
  (def generation:*Generation p)
  (when generation->native (gp-llm-generation-free generation->native))
  (return 0))

(function mark-generation :static [p:*void size:size_t] -> int
  (def generation:*Generation p)
  (when generation->session (janet-mark (janet-wrap-abstract generation->session)))
  (return 0))

(abstract-type Model :name "gp/llm-model" :gc gc-model)
(abstract-type Session :name "gp/llm-session" :gc gc-session :gcmark mark-session)
(abstract-type Generation :name "gp/llm-generation" :gc gc-generation :gcmark mark-generation)

(cfunction load-model
  "Load a local GGUF model."
  [path:string mmap:bool] -> *Model
  (def (message (array char 512)) nil)
  (def native:*GpLlmModel (gp-llm-model-load path mmap (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (def model:*Model (janet-abstract Model-ATP (sizeof Model)))
  (set model->native native)
  (return model))

(cfunction model-description "Return the model description." [model:*Model] -> string
  (def (*text (const char)) (gp-llm-model-description model->native))
  (return (janet-cstring text)))

(cfunction model-size "Return the model weight size in bytes." [model:*Model] -> number
  (return (cast double (gp-llm-model-size model->native))))

(cfunction model-parameters "Return the model parameter count." [model:*Model] -> number
  (return (cast double (gp-llm-model-parameters model->native))))

(cfunction model-context-size "Return the model training context size." [model:*Model] -> int
  (return (gp-llm-model-context-size model->native)))

(cfunction tokenize
  "Convert UTF-8 text to model token IDs."
  [model:*Model text:string add-special:bool] -> array
  (def text-length:int32_t (janet-string-length text))
  (def count:int32_t (gp-llm-tokenize model->native text text-length NULL 0 add-special))
  (if (== count INT32_MIN) (janet-panic "text is too large to tokenize"))
  (if (< count 0) (set count (- count)))
  (def *tokens:int32_t (janet-malloc (* (+ count 1) (sizeof int32_t))))
  (unless tokens JANET_OUT_OF_MEMORY)
  (def actual:int32_t (gp-llm-tokenize model->native text text-length tokens count add-special))
  (when (< actual 0) (janet-free tokens) (janet-panic "failed to tokenize text"))
  (def result:*JanetArray (janet-array actual))
  (def i:int32_t 0)
  (while (< i actual)
    (janet-array-push result (janet-wrap-integer (aref tokens i)))
    (++ i))
  (janet-free tokens)
  (return result))

(cfunction detokenize
  "Convert model token IDs to UTF-8 text."
  [model:*Model values:array remove-special:bool] -> string
  (def count:int32_t values->count)
  (def *tokens:int32_t (janet-malloc (* (+ count 1) (sizeof int32_t))))
  (unless tokens JANET_OUT_OF_MEMORY)
  (def i:int32_t 0)
  (while (< i count)
    (set (aref tokens i) (janet-getinteger values->data i))
    (++ i))
  (def needed:int32_t (gp-llm-detokenize model->native tokens count NULL 0 remove-special))
  (if (< needed 0) (set needed (- needed)))
  (def *text:char (janet-malloc (+ needed 1)))
  (unless text (janet-free tokens) JANET_OUT_OF_MEMORY)
  (def actual:int32_t (gp-llm-detokenize model->native tokens count text needed remove-special))
  (janet-free tokens)
  (when (< actual 0) (janet-free text) (janet-panic "failed to detokenize tokens"))
  (def result:JanetString (janet-string (cast (* uint8_t) text) actual))
  (janet-free text)
  (return result))

(cfunction new-session
  "Create a mutable inference session for a model."
  [model:*Model context-size:int batch-size:int threads:int] -> *Session
  (def (message (array char 512)) nil)
  (def native:*GpLlmSession
    (gp-llm-session-new model->native context-size batch-size threads (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (def session:*Session (janet-abstract Session-ATP (sizeof Session)))
  (set session->native native)
  (set session->model model)
  (return session))

(cfunction reset "Clear a session's inference memory." [session:*Session] -> bool
  (when (gp-llm-session-busy session->native) (janet-panic "cannot reset a busy session"))
  (gp-llm-session-reset session->native)
  (return true))

(cfunction session-context-size "Return the actual session context size." [session:*Session] -> int
  (return (gp-llm-session-context-size session->native)))

(cfunction start-generation
  "Start generation and return its resumable native state."
  [session:*Session input:string max-tokens:int temperature:number top-k:int top-p:number min-p:number seed:uint32_t] -> *Generation
  (def (message (array char 512)) nil)
  (def native:*GpLlmGeneration
    (gp-llm-generation-new session->native input (janet-string-length input)
                           max-tokens temperature top-k top-p min-p seed
                           (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (def generation:*Generation (janet-abstract Generation-ATP (sizeof Generation)))
  (set generation->native native)
  (set generation->session session)
  (return generation))

(cfunction generation-step
  "Return [has-piece? piece] for the next generated text step."
  [generation:*Generation] -> JanetTuple
  (def (*piece (const char)) NULL)
  (def piece-length:int32_t 0)
  (def (message (array char 512)) nil)
  (def status:int (gp-llm-generation-step generation->native (addr piece) (addr piece-length)
                                           (addr (aref message 0)) 512))
  (if (< status 0) (janet-panic (addr (aref message 0))))
  (def result:*Janet (janet-tuple-begin 2))
  (set (aref result 0) (? (== status 0) (janet-wrap-false) (janet-wrap-true)))
  (set (aref result 1)
       (? (== status 0)
         (janet-wrap-nil)
         (janet-wrap-string (janet-string (cast (* uint8_t) piece) piece-length))))
  (return (janet-tuple-end result)))

(module-entry "llm-native")
