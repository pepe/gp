(import gp/term)

(defmacro screen
  "Renders body forever"
  [& body]
  ~(defer (,term/shutdown)
     (,term/init)
     ,;body
     ,term/present))

(defn at
  "Prints `text` at `x`, `y`"
  [x y text]
  (term/print))

(defn get-event
  "Polls for new event"
  []
  (def e (term/init-event))
  (term/poll e)
  e)
