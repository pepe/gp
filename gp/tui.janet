(use spork/misc)
(import /build/gp/term)

(defmacro screen
  "Renders `body` in init shutdown block"
  [& body]
  ~(defer (,term/shutdown)
     (,term/init)
     ,;body))

(defn at
  "Prints `text` at `x`, `y`"
  [x y text]
  (term/print x y (dyn :fg term/default) (dyn :bg term/default) (string text)))

(defmacro on-event
  "Polls for event bind it to `event`, execute `body` and present. Forever."
  [& body]
  ~(let [event (,term/init-event)]
     (forever (,term/poll event)
       ,;body
       (,term/present))))
