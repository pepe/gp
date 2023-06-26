# Simple fuzzy finder example
(import spork/utf8)
(import /gp/tui)
(import /build/gp/term)
(import /build/gp/data/fuzzy)

(def model
  (let [all (map |@[$ 0 []] (string/split "\n" (file/read stdin :all)))]
    @{:input @[] :sel 0 :position 0 "" all
      :prompt |(string/format "%i/%i>" ($ :count-all) ($ :count-all))
      :string-input |(string/join ($ :input))
      :clear |(merge-into $ {:input @[] :position 0 :sel 0})
      :add (fn [self ch]
             (put self :sel 0)
             (let
               [osi (:string-input self)
                c (string (utf8/encode-rune ch))]
               (array/push (self :input) c)
               (def si (:string-input self))
               (update self :position inc)
               (put self si
                    (sort-by |(- ($ 1))
                             (seq [[i _ _] :in (self osi)
                                   :let [sc (fuzzy/score si i)]
                                   :when (and sc (> sc fuzzy/score-min))]
                               [i sc (fuzzy/positions si i)])))))
      :remove-last |(-> $
                        (update :position dec)
                        (get :input)
                        array/pop)
      :move-select (fn [self mfn maxc]
                     (let [tms (mfn (self :sel))
                           cl (min maxc (:count-current self))]
                       (put self :sel
                            (cond
                              (neg? tms) 0
                              (>= tms cl) (dec cl)
                              tms))))
      :current |($ (:string-input $))
      :count-all (length all)
      :count-current |(length (:current $))
      :result |(or (get-in $ [(:string-input $) ($ :sel) 0])
                   (:string-input $))}))

(var list-height 0)

(defn list [model]
  (loop [[y [s _ ps]] :pairs (:current model)
         :while (< y list-height)]
    (var xv 0)
    (var i 0)
    (def w term/width)
    (def rps (reverse ps))
    (def inv (= (model :sel) y))
    (var cps (array/pop rps))
    (while (< i (min w (length s)))
      (let [cl (utf8/prefix->width (s i))
            bg (if inv term/yellow term/default)
            fg (if (= i cps)
                 (do
                   (set cps (array/pop rps))
                   (bor term/bold (if inv term/red term/green)))
                 (if inv term/black term/default))]
        (term/print xv (inc y) fg bg (slice s i (+ i cl)))
        (+= i cl)
        (++ xv)))))

(defn main [&]
  (tui/screen
    (set list-height (dec (term/height)))
    (let [prompt (:prompt model)]
      (tui/render
        (tui/at 0 0 prompt)
        (term/set-cursor (inc (length prompt)) 0)
        (list model)))
    (tui/on-event
      (def ch (term/ch event))
      (if (zero? ch)
        (tui/on-key
          term/key-ctrl-k (:clear model)
          [term/key-ctrl-d term/key-enter term/key-ctrl-j] (break)
          term/key-backspace2 (unless (empty? (model :input))
                                (:remove-last model)
                                (tui/at (model :position) 0 " ")
                                (term/set-cursor (model :position) 0))
          [term/key-ctrl-c term/key-ctrl-q term/key-esc]
          (do (term/shutdown) (os/exit 1))
          [term/key-arrow-down term/key-tab term/key-ctrl-n]
          (:move-select model inc list-height)
          [term/key-arrow-up term/key-ctrl-p term/key-back-tab]
          (:move-select model dec list-height))
        (:add model ch))
      (let [prompt (:prompt model)
            lp (inc (length prompt))]
        (tui/render
          (tui/at 0 0 prompt)
          (tui/at lp 0 (:string-input model))
          (term/set-cursor (+ lp (model :position)) 0)
          (list model)))))
  (let [si (:string-input model)] (print (:result model))))
