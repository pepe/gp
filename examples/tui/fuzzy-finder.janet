# Simple fuzzy finder example
(use spork/misc spork/utf8 /gp/tui gp/data/fuzzy)

(def Screen
  @{:input @[] :sel 0 :position 0
    :prompt |(string/format "%i/%i>" ($ :count-all) ($ :count-all))
    :string-input |(string/join ($ :input))
    :clear |(merge-into $ {:input @[] :position 0 :sel 0})
    :add (fn [self ch]
           (put self :sel 0)
           (let
             [osi (:string-input self)
              c (string (encode-rune ch))]
             (array/push (self :input) c)
             (def si (:string-input self))
             (update self :position inc)
             (put self si
                  (sort-by |(- ($ 1))
                           (seq [[i _ _] :in (self osi)
                                 :let [sc (score si i)]
                                 :when (and sc (> sc score-min))]
                             [i sc (positions si i)])))))
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
    :count-current |(length (:current $))
    :result |(or (get-in $ [(:string-input $) ($ :sel) 0])
                 (:string-input $))})

(defn make-screen
  "Makes new screen with items"
  [items]
  (make Screen "" (map |@[$ 0 []] items) :count-all (length items)))

(var list-height 0)

(defn list
  "Lists head of items"
  [model]
  (loop [[y [s _ ps]] :pairs (:current model)
         :while (< y list-height)]
    (var xv 0)
    (var i 0)
    (def w term/width)
    (def rps (reverse ps))
    (def inv (= (model :sel) y))
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
        (++ xv)))))

(defn main
  "Main program"
  [_ & items]
  (def finder-screen (make-screen items))
  (screen
    (set list-height (dec (term/height)))
    (let [prompt (:prompt finder-screen)]
      (render
        (at 0 0 prompt)
        (term/set-cursor (inc (length prompt)) 0)
        (list finder-screen)))
    (on-event
      (def ch (term/ch event))
      (if (zero? ch)
        (on-key
          term/key-ctrl-k (:clear finder-screen)
          [term/key-ctrl-d term/key-enter term/key-ctrl-j] (break)
          term/key-backspace2 (unless (empty? (finder-screen :input))
                                (:remove-last finder-screen)
                                (at (finder-screen :position) 0 " ")
                                (term/set-cursor (finder-screen :position) 0))
          [term/key-ctrl-c term/key-ctrl-q term/key-esc]
          (do (term/shutdown) (os/exit 1))
          [term/key-arrow-down term/key-tab term/key-ctrl-n]
          (:move-select finder-screen inc list-height)
          [term/key-arrow-up term/key-ctrl-p term/key-back-tab]
          (:move-select finder-screen dec list-height))
        (:add finder-screen ch))
      (let [prompt (:prompt finder-screen)
            lp (inc (length prompt))]
        (render
          (at 0 0 prompt)
          (at lp 0 (:string-input finder-screen))
          (term/set-cursor (+ lp (finder-screen :position)) 0)
          (list finder-screen)))))
  (print (:result finder-screen)))
