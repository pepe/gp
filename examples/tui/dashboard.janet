# A dry run of a terminal dashboard on gp/tui: the live line on top with
# its explanation under it, then the focused todo, the tracking, the MITs
# and the todos, as many as there are, scrolling.
#
# Typing goes to the live line. Ctrl+Enter (or Alt+Enter) confirms,
# Enter breaks the line. Esc leaves the line, i takes you back to it.
# Outside it j/k, arrows, PgUp/PgDn and the wheel scroll the todos.
# q outside the line or Ctrl+C anywhere quits.
#
# Commands: b begin, e end, d N done, f N focus, n text note,
# + text new todo. An empty line confirms the default of the state.
(use gp/events)
(import gp/tui)

(def state
  @{:editor (tui/make-editor {:prompt "> "})
    :input? true
    :scroll 0
    :focused "Write the invoice"
    :tracking nil
    :notes @[]
    :message nil
    :mits @["Call the bank" "Review the pull request"]
    :todos (array/concat @["Write the invoice" "Call the bank"
                           "Review the pull request"]
                         (seq [i :range [1 60]]
                           (string "Something else to do, number " i)))})

(defn duration [seconds]
  (string/format "%d:%02d:%02d" (div seconds 3600)
                 (% (div seconds 60) 60) (% seconds 60)))

(defn parse [text]
  (def t (string/trim text))
  (cond
    (empty? t) (if (state :tracking) [:end] [:begin])
    (= t "b") [:begin]
    (= t "e") [:end]
    (string/has-prefix? "+ " t) [:new (string/slice t 2)]
    (string/has-prefix? "n " t) [:note (string/slice t 2)]
    (peg/match '(* (<- (set "df")) (any " ") (number :d+) -1) t)
    (let [[l n] (peg/match '(* (<- (set "df")) (any " ") (number :d+) -1) t)]
      [(if (= l "d") :done :focus) n])
    [:unknown t]))

(defn explain [text]
  (def todos (state :todos))
  (match (parse text)
    [:begin] (if (state :tracking)
               "Already tracking."
               (string "Confirm ⌃↵  Begin tracking of " (state :focused)))
    [:end] (if (state :tracking)
             (string "Confirm ⌃↵  End tracking of " (state :focused))
             "Not tracking.")
    [:new todo] (string "Confirm ⌃↵  Create todo " todo)
    [:note note] (string "Confirm ⌃↵  Add note " note)
    [:unknown _] "Unknown command."
    [cmd n] (if (<= 1 n (length todos))
              (string "Confirm ⌃↵  " (if (= cmd :done) "Mark done " "Focus ")
                      (todos (dec n)))
              (string "Select an item between 1–" (length todos) "."))
    _ "Unknown command."))

(defn run [text]
  (def todos (state :todos))
  (put state :message
       (match (parse text)
         [:begin] (unless (state :tracking)
                    (put state :tracking (os/time))
                    (string "Began tracking of " (state :focused)))
         [:end] (when-let [start (state :tracking)]
                  (put state :tracking nil)
                  (string "Ended after " (duration (- (os/time) start))))
         [:new todo] (do (array/push todos todo) (string todo " created"))
         [:note note] (do (array/push (state :notes) note)
                        (string "Added note " note))
         [:done n] (when (<= 1 n (length todos))
                     (def todo (todos (dec n)))
                     (array/remove todos (dec n))
                     (string todo " done"))
         [:focus n] (when (<= 1 n (length todos))
                      (put state :focused (todos (dec n)))
                      (string "Focused " (state :focused)))
         _ "Unknown command.")))

(defn render [term]
  (def [rows cols] (tui/size))
  (def ed (state :editor))
  (def [live cursor] (tui/editor/render ed cols))
  (def todos (state :todos))
  (def laid
    (tui/stack
      rows
      live
      [(tui/styled :dim (string "  " (explain (tui/editor/text ed))))
       (if-let [m (state :message)] (tui/styled :cyan (string "  " m)) "")]
      (tui/rule cols)
      [(tui/columns ["Focused: " (tui/styled :bold (state :focused))]
                    (tui/styled :dim (string (length (state :notes)) " notes"))
                    cols)]
      (if-let [start (state :tracking)]
        [["Tracking " (tui/styled :yellow (duration (- (os/time) start)))]]
        [])
      (seq [[i mit] :pairs (state :mits)]
        (tui/styled :green (string "MIT " (inc i) " " mit)))
      (tui/rule cols)
      @{:flex (seq [[i todo] :pairs todos]
                [(tui/styled :dim (string/format "%3d " (inc i))) todo])
        :scroll (state :scroll)}))
  (put state :scroll (laid :scroll))
  (tui/present term (laid :lines) (if (state :input?) cursor)))

(defn on-key [term k]
  (def key (k :key))
  (def [_ cols] (tui/size))
  (def page (max 1 (- (first (tui/size)) 10)))
  (make-event
    {:update
     (fn [_ _]
       (cond
         (= key :ctrl-c) (do (tui/close term) (os/exit 0))
         (= key :wheel) (update state :scroll + (* 3 (k :dy)))
         (state :input?)
         (if (= key :esc)
           (put state :input? false)
           (if (= :submit (tui/editor/key (state :editor) k cols))
             (do (run (tui/editor/text (state :editor)))
               (tui/editor/submit (state :editor)))))
         (case [key (k :text)]
           [:char "q"] (do (tui/close term) (os/exit 0))
           [:char "i"] (put state :input? true)
           [:char "j"] (update state :scroll inc)
           [:char "k"] (update state :scroll dec)
           [:down nil] (update state :scroll inc)
           [:up nil] (update state :scroll dec)
           [:pgdn nil] (update state :scroll + page)
           [:pgup nil] (update state :scroll - page))))
     :effect (fn [&] (render term))}
    "key"))

(defn main [&]
  (def manager (make-manager state))
  (tui/with-terminal [term {}]
    (:transact manager
               (make-effect (fn [&] (render term)))
               (make-watch (fn [&] (tui/key-producer term |(on-key term $))))
               (make-watch (fn [&] (tui/ticker 1 |(make-effect (fn [&] (render term)))))))
    (:await manager)))
