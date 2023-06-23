# Simple fuzzy finder example
(import spork/utf8)
(import /gp/tui)
(import /build/gp/term)
(import /build/gp/data/fuzzy)
(use /gp/data/schema /gp/utils)

(var input @"")
(var p 0)
(def cache @{"" (map |@[$ 0] (string/split "\n" (file/read stdin :all)))})
(def al (length (cache "")))
(var sel 0)

(defn match-and-score [d s]
  (seq [[i _] :in d
        :let [sc (fuzzy/score s i)]
        :when (and sc (> sc fuzzy/score-min))]
    [i sc]))

(defn match-n-sort [d s]
  (if (empty? d) (break d))
  (sort-by |(- ($ 1))
           (match-and-score d s)))

(defn render-items [items]
  (loop [[i [s _]] :pairs items
         :while (< i (term/height))]
    (when (= sel i)
      (setdyn :fg term/black)
      (setdyn :bg term/white))
    (tui/at 0 (inc i) s)
    (setdyn :fg term/default)
    (setdyn :bg term/default)))

(defn select [mfn]
  (def tms (mfn sel))
  (def cl (length (cache (string input))))
  (set sel
       (cond
         (neg? tms) 0
         (>= tms cl) (dec cl)
         tms)))

(tui/screen
  (var prompt (string/format "%i/%i>" al al))
  (tui/at 0 0 prompt)
  (term/set-cursor (inc (length prompt)) 0)
  (term/present)
  (render-items (cache ""))
  (term/present)
  (var oc 0)
  (tui/on-event
    (def ch (term/ch event))
    (if (zero? ch)
      (tui/on-key
        term/key-enter (break)
        term/key-backspace2 (unless (empty? input)
                              (-- p)
                              (tui/at p 0 " ")
                              (term/set-cursor p 0)
                              (buffer/popn input (utf8/prefix->width oc)))
        [term/key-arrow-down term/key-tab term/key-ctrl-j] (select inc)
        [term/key-arrow-up term/key-ctrl-k term/key-back-tab] (select dec)
        term/key-ctrl-c (do (term/shutdown) (os/exit 1)))
      (let
        [oi (string input)
         c (string (utf8/encode-rune ch))]
        (++ p)
        (buffer/push input c)
        (put cache (string input)
             (match-n-sort (cache oi) input))
        (set oc (c 0))))
    (term/clear)
    (set prompt (string/format "%i/%i>" (length (cache (string input))) al))
    (tui/at 0 0 prompt)
    (def lp (inc (length prompt)))
    (tui/at lp 0 (string input))
    (term/set-cursor (+ lp p) 0)
    (render-items (cache (string input)))))
(print (get-in cache [(string input) sel 0]))
(comment)
