(use spork/misc spork/utf8)
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
                    [[one-of [term/key 'event] ;(map |(symbol 'term/key- $) pred)] act]
                    [['= [term/key 'event] (symbol 'term/key- pred)] act])))
  (tuple 'cond ;res))

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
    :render (fn [self]
              (defer (term/shutdown)
                (term/init)
                (def event (term/init-event))
                (forever
                  (let [prompt (:prompt self)
                        lp (inc (length prompt))]
                    (term/clear)
                    (term/print 0 0 term/default term/default (string prompt " " (self :string-input)))
                    (term/set-cursor (+ lp (:position self)) 0)
                    (loop [[y [s sc ps]] :pairs (:current self)
                           :while (< y (term/height))]
                      (var xv 0)
                      (var i 0)
                      (def w term/width)
                      (def rps (reverse ps))
                      (def inv (= (self :sel) y))
                      (var cps (array/pop rps))
                      (while (< i (min w (length s)))
                        (let [cl (prefix->width (s i))
                              bg (if inv term/yellow term/default)
                              fg (if (= i cps)
                                   (do
                                     (set cps (array/pop rps))
                                     (bor term/bold (if inv term/red term/green)))
                                   (if inv term/black term/default))]
                          (term/print xv (inc y) fg bg (slice s i (+ i cl)))
                          (+= i cl)
                          (++ xv))))
                    (term/present))
                  (term/poll event)
                  (let [ch (term/ch event)
                        osi (self :string-input)]
                    (if (zero? ch)
                      (on-key
                        ctrl-k (merge-into self {:input @[] :sel 0})
                        [enter ctrl-d ctrl-j] (break)
                        [ctrl-h backspace2] (unless (empty? (self :input))
                                              (put self :sel 0)
                                              (array/pop (self :input))
                                              (put self :string-input (string ;(self :input))))
                        [ctrl-c ctrl-q esc] (do (term/shutdown) (os/exit 1))
                        [arrow-down tab ctrl-n] (:move-select self inc)
                        [arrow-up ctrl-p back-tab] (:move-select self dec))
                      (do
                        (-> self
                            (put :sel 0)
                            (update :input array/push (string (encode-rune ch))))
                        (put self :string-input (string ;(self :input)))
                        (put self (self :string-input) (score-n-order-positions (self :string-input) (self osi))))))))
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
