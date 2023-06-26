(use spork/misc)
(import gp/term :export true)
(import /gp/utils)

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
  "Polls for event bind it to `event` and execute `body` with it. Forever."
  [& body]
  ~(let [event (,term/init-event)]
     (forever (,term/poll event) ,;body)))

(defmacro on-key
  "Matches current `event`'s `key` against clauses.
  When clause is single it tries to equal when it is a tuple
  of keys it checks it is one of them."
  [& clauses]
  (def res @[])
  (each [pred act] (partition 2 clauses)
    (array/concat res
                  (if (indexed? pred)
                    [[utils/one-of [term/key 'event] ;pred] act]
                    [['= [term/key 'event] pred] act])))
  (tuple 'cond ;res))

(defmacro render
  "Convenience macro with `term/clear` at start of the `body`
  and `term/present` at its end."
  [& body]
  ~(do
     (,term/clear)
     ,;body
     (,term/present)))
