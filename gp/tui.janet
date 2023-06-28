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
  "Renders `body` in init shutdown block"
  [& body]
  ~(defer (,term/shutdown)
     (,term/init)
     ,;body))

(defmacro on-event
  "Polls for event bind it to `event` and execute `body` with it. Forever."
  [& body]
  ~(let [event (,term/init-event)]
     (,term/poll event) ,;body))

(def Chooser
  "Backing model for the chooser"
  @{:input @[] :sel 0 :string-input ""
    :position |(length ($ :input))
    :prompt |(string/format ($ :prompt-format) (length (:current $)) ($ :count-all))
    :move-select (fn [self mfn]
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
                     (or (get-in $ [($ :string-input) ($ :sel) 0])
                         ($ :string-input)))
    :list
    (fn [self]
      (loop [[y [s sc ps]] :pairs (:current self)
             :while (< y (term/height))]
        (var xv 0)
        (var i 0)
        (def w (min term/width (monowidth s)))
        (def rps (reverse ps))
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
        (forever
          (let [prompt (:prompt self)
                lp (inc (monowidth prompt))]
            (term/clear)
            (term/print 0 0 term/default term/default (string prompt " " (self :string-input)))
            (term/set-cursor (+ lp (:position self)) 0)
            (:list self)
            (term/present))
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
                  [arrow-down tab ctrl-n] (:move-select self inc)
                  [arrow-up ctrl-p back-tab] (:move-select self dec))
                (-> self
                    (put :sel 0)
                    (update :input array/push (string (encode-rune ch)))
                    (put :string-input (string ;(self :input)))
                    (put (self :string-input) (score-n-order-positions (self :string-input) (self osi)))))))))
      self)})

(defn make-chooser
  ```
  Makes new chooser with `items`. It takes `prefix` which will be stripped
  from each item and then prepended to result.
  
  See `Chooser` prototype.
  ```
  [prefix items &opt prompt-format]
  (default prompt "%i/%i>")
  (def transform
    (if (empty? prefix) identity |(string/replace prefix "" $)))
  (make Chooser "" (map |@[(transform $) 0 []] items)
        :prefix prefix :count-all (length items) :prompt-format prompt-format))
