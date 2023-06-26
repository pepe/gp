# Simple fuzzy finder example
(import spork/utf8)
(import /gp/tui)
(import /build/gp/term)
(import /build/gp/data/fuzzy)

(def model
  (let [all (map |@[$ 0] (string/split "\n" (file/read stdin :all)))]
    @{:input @[] :sel 0 :position 0 "" all
      :string-input (fn [self] (string/join (self :input)))
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
                             (seq [[i _] :in (self osi)
                                   :let [sc (fuzzy/score si i)]
                                   :when (and sc (> sc fuzzy/score-min))]
                               [i sc (fuzzy/positions si i)])))))
      :remove-last |(do
                      (update $ :position dec)
                      (array/pop ($ :input)))
      :move-select (fn [self mfn maxc]
                     (def tms (mfn (self :sel)))
                     (def cl (min maxc (:count-current self)))
                     (put self :sel
                          (cond
                            (neg? tms) 0
                            (>= tms cl) (dec cl)
                            tms)))
      :current (fn [self] (self (:string-input self)))
      :selected |(get-in $ [(:string-input $) ($ :sel) 0])
      :count-all (length all)
      :count-current |(length (:current $))}))

(defn list [model]
  (loop [[i [s _]] :pairs (:current model)
         :while (< i (dec (term/height)))]
    (when (= (model :sel) i)
      (setdyn :fg term/black)
      (setdyn :bg term/white))
    (tui/at 0 (inc i) s)
    (setdyn :fg term/default)
    (setdyn :bg term/default)))

(tui/screen
  (var prompt (string/format "%i/%i>" (model :count-all) (model :count-all)))
  (tui/render
    (tui/at 0 0 prompt)
    (term/set-cursor (inc (length prompt)) 0)
    (list model))
  (tui/on-event
    (def ch (term/ch event))
    (if (zero? ch)
      (tui/on-key
        [term/key-ctrl-d term/key-enter] (break)
        term/key-backspace2 (unless (empty? (model :input))
                              (:remove-last model)
                              (tui/at (model :position) 0 " ")
                              (term/set-cursor (model :position) 0))
        [term/key-ctrl-c term/key-ctrl-q term/key-esc]
        (do (term/shutdown) (os/exit 1))
        [term/key-arrow-down term/key-tab term/key-ctrl-j]
        (:move-select model inc (dec (term/height)))
        [term/key-arrow-up term/key-ctrl-k term/key-back-tab]
        (:move-select model dec (dec (term/height))))
      (:add model ch))
    (set prompt (string/format "%i/%i>"
                               (:count-current model)
                               (model :count-all)))
    (def lp (inc (length prompt)))
    (tui/render
      (tui/at 0 0 prompt)
      (tui/at lp 0 (:string-input model))
      (term/set-cursor (+ lp (model :position)) 0)
      (list model))))

(let [si (:string-input model)] (print (or (:selected model) si)))
