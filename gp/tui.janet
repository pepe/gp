(use spork/misc spork/utf8 spork/rawterm)
(use ./utils ./data/scorer)

(import gp/term :export true)

(defmacro on-key
  "Matches current `event`'s `key` against clauses.
  When clause is single it tries to equal when it is a tuple
  of keys it checks it is one of them."
  [& clauses]
  (def res @[])
  (each [pred act] (partition 2 clauses)
    (array/concat res
                  (if (indexed? pred)
                    [[one-of [:key 'event] ;(map |(symbol 'term/key- $) pred)] act]
                    [['= [:key 'event] (symbol 'term/key- pred)] act])))
  (tuple 'cond ;res))

(defmacro screen
  "Forever renders `body` in init shutdown block"
  [& body]
  ~(defer (,term/shutdown)
     (,term/init)
     (forever ,;body)))

(defmacro on-event
  "Polls for event bind it to `event` and execute `body` with it. Forever."
  [& body]
  ~(let [event (,term/init-event)]
     (,term/poll event) ,;body))

(defmacro render
  "Convenience macro, that `clear`s terminal before `body` 
  and `present`s after."
  [& body]
  ~(do (,term/clear) ,;body (,term/present)))

(defn prompt
  "Print prompt with `parts` with cursor at the end"
  [& parts]
  (def p (string/join parts " "))
  (term/print 0 0 term/default term/default p)
  (term/set-cursor (monowidth p) 0))

(def Chooser
  "Backing model for the chooser"
  @{:input @[] :sel 0 :string-input "" :prompt-format "%i/%i>"
    :position |(length ($ :input))
    :prompt |(string/format ($ :prompt-format) (length (:current $)) ($ :count-all))
    :move-sel (fn [self mfn]
                (let [tms (mfn (self :sel))
                      cl (min (self :list-height)
                              (length (:current self)))]
                  (put self :sel
                       (cond
                         (neg? tms) 0
                         (>= tms cl) (dec cl)
                         tms))))
    :current |($ ($ :string-input))
    :result |(string ($ :prefix)
                     (or (get-in $ [($ :string-input) ($ :sel)])
                         ($ :string-input)))
    :list
    (fn [self]
      (loop [[y s] :pairs (:current self)
             :while (< y (term/height))]
        (var xv 0)
        (var i 0)
        (def w (min term/width (monowidth s)))
        (def rps (reverse (positions (self :string-input) s)))
        (def inv (= (self :sel) y))
        (var cps (array/pop rps))
        (while (< i w)
          (let [cl (prefix->width (s i))
                bg (if inv term/reverse term/default)
                fg (if (= i cps)
                     (do
                       (set cps (array/pop rps))
                       (bor term/bold term/green))
                     (if inv term/reverse term/default))]
            (term/print xv (inc y) fg bg (slice s i (+ i cl)))
            (+= i cl)
            (++ xv)))))
    :render
    (fn [self]
      (screen
        (render
          (prompt (:prompt self) (self :string-input))
          (:list self))
        (on-event
          (let [ch (:ch event)
                osi (self :string-input)]
            (if (zero? ch)
              (on-key
                ctrl-k (merge-into self {:input @[] :sel 0})
                [enter ctrl-d ctrl-j] (break)
                [ctrl-h backspace2] (if-not (empty? (self :input))
                                      (-> self
                                          (put :sel 0)
                                          (update :input array/remove -2)
                                          (put :string-input (string ;(self :input)))))
                [ctrl-c ctrl-q esc] (do (term/shutdown) (os/exit 1))
                [arrow-down tab ctrl-n] (:move-sel self inc)
                [arrow-up ctrl-p back-tab] (:move-sel self dec))
              (do
                (-> self
                    (put :sel 0)
                    (update :input array/push (string (encode-rune ch)))
                    (put :string-input (string ;(self :input))))
                (if-not (:current self)
                  (put self (self :string-input) (order-scores (self :string-input) (self osi)))))))))
      self)})

(defn make-chooser
  ```
  Makes new chooser with `items`. It takes `config` table to which `Chooser` 
  prototype will be set. Updated config will be returned.
  ```
  [items &opt config]
  (default config @{})
  (assert (indexed? items) "Items must be indexed collection.")
  (assert (table? config) "Config must be table.")
  (merge-into config {"" items :count-all (length items)})
  (table/setproto config Chooser))
