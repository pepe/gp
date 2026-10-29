(import spork/rawterm)
(import spork/utf8)
(use ./events)
(import ./data/scorer)

(def- windows? (= :windows (os/which)))

# Styles

(def sgr
  "SGR codes for the style keywords a piece of a line can carry."
  {:bold 1 :dim 2 :italic 3 :underline 4 :reverse 7
   :black 30 :red 31 :green 32 :yellow 33
   :blue 34 :magenta 35 :cyan 36 :white 37 :gray 90
   :bright-red 91 :bright-green 92 :bright-yellow 93
   :bright-blue 94 :bright-magenta 95 :bright-cyan 96 :bright-white 97
   :bg-black 40 :bg-red 41 :bg-green 42 :bg-yellow 43
   :bg-blue 44 :bg-magenta 45 :bg-cyan 46 :bg-white 47 :bg-gray 100})

(defn styled
  ```
  Returns a piece of a line: `text` drawn in `style`, a keyword of `sgr`
  or an indexed of them. A number among them is a raw SGR code.
  ```
  [style text]
  {:style style :text text})

(defn- sgr-of [style]
  (def codes
    (map |(if (number? $) $ (assert (sgr $) (string "unknown style " $)))
         (if (indexed? style) style [style])))
  (string "\e[" (string/join (map string codes) ";") "m"))

(defn- clean
  "Text with control bytes drawn as spaces, so none moves the cursor."
  [text]
  (string/from-bytes ;(map |(if (< $ 32) 32 $) text)))

(defn- pieces [line]
  (if (indexed? line) line [line]))

(defn- text-of [piece]
  (if (bytes? piece) piece (piece :text)))

(defn line-width
  ```
  Returns the columns `line` takes. A line is a piece or an indexed of
  pieces, each a string or `styled`.
  ```
  [line]
  (sum (map |(rawterm/monowidth (text-of $)) (pieces line))))

(defn fit
  "Returns `line` as a string of escapes cut to at most `cols` columns."
  [line cols]
  (def out @"")
  (var left cols)
  (each piece (pieces line)
    (def style (if (bytes? piece) nil (piece :style)))
    (when (pos? left)
      (def part (rawterm/slice-monowidth (clean (text-of piece)) left))
      (-= left (rawterm/monowidth part))
      (if style
        (buffer/push out (sgr-of style) part "\e[0m")
        (buffer/push out part))))
  (string out))

(defn columns
  "Returns a line of `left` and `right` pieces, `right` flush to `cols`."
  [left right cols]
  (def gap (max 1 (- cols (line-width left) (line-width right))))
  [;(pieces left) (string/repeat " " gap) ;(pieces right)])

(defn rule
  "Returns a line of `cols` times `ch`, by default a thin dim rule."
  [cols &opt ch style]
  (default ch "─")
  (default style :dim)
  [(styled style (string/repeat ch cols))])

# Keys

(def- csi-letters
  {(chr "A") :up (chr "B") :down (chr "C") :right (chr "D") :left
   (chr "H") :home (chr "F") :end
   (chr "P") :f1 (chr "Q") :f2 (chr "R") :f3 (chr "S") :f4})

(def- csi-tildes
  {1 :home 2 :insert 3 :delete 4 :end 5 :pgup 6 :pgdn 7 :home 8 :end
   15 :f5 17 :f6 18 :f7 19 :f8 20 :f9 21 :f10 23 :f11 24 :f12})

(defn- with-mods
  "Puts the modifiers the xterm number `m` encodes on `key`."
  [key m]
  (def bits (- (or m 1) 1))
  (def k (table ;(kvs key)))
  (if (pos? (band bits 1)) (put k :shift true))
  (if (pos? (band bits 2)) (put k :alt true))
  (if (pos? (band bits 4)) (put k :ctrl true))
  (case [(k :key) (truthy? (k :ctrl)) (truthy? (k :alt))]
    [:enter true false] (put k :key :ctrl-enter)
    [:enter false true] (put k :key :alt-enter))
  (table/to-struct k))

(defn- key-of-code [code]
  (case code
    13 {:key :enter}
    9 {:key :tab}
    27 {:key :esc}
    127 {:key :backspace}
    {:key :char :text (string (utf8/encode-rune code))}))

(defn- ctrl-key [c]
  (case c
    13 {:key :enter}
    10 {:key :ctrl-enter}
    9 {:key :tab}
    8 {:key :backspace}
    0 {:key :ctrl-space}
    (if (<= 1 c 26)
      {:key (keyword "ctrl-" (string/from-bytes (+ 96 c)))})))

(defn- csi-key [params final]
  (def nums (map |(or (scan-number $) 0) (string/split ";" params)))
  (cond
    (csi-letters final) (with-mods {:key (csi-letters final)} (get nums 1))
    (= final (chr "Z")) {:key :tab :shift true}
    (= final (chr "u")) (with-mods (key-of-code (nums 0)) (get nums 1))
    (and (= final (chr "~")) (= 27 (nums 0)))
    (with-mods (key-of-code (get nums 2 0)) (get nums 1))
    (and (= final (chr "~")) (csi-tildes (nums 0)))
    (with-mods {:key (csi-tildes (nums 0))} (get nums 1))))

(defn- mouse-key [params final]
  (def [b col row] (map scan-number (string/split ";" (slice params 1))))
  (if (pos? (band b 64))
    {:key :wheel :dy (if (odd? b) 1 -1) :row row :col col}
    {:key :mouse :button b :row row :col col :press (= final (chr "M"))}))

(def- paste-start "\e[200~")
(def- paste-end "\e[201~")

(defn- utf8-length [c]
  (cond (< c 0x80) 1 (= 0xC0 (band c 0xE0)) 2
        (= 0xE0 (band c 0xF0)) 3 (= 0xF0 (band c 0xF8)) 4))

(defn- decode-one
  ```
  Decodes the key starting at `i` of `b`. Returns [key used], with a nil
  key for bytes skipped, or nil when the key is not whole yet. When
  `final`, no more bytes are coming, so a lone escape is the Esc key.
  ```
  [b i final]
  (def n (length b))
  (def c (b i))
  (cond
    (= c 27)
    (if (= (inc i) n)
      (if final [{:key :esc} 1])
      (let [c2 (b (inc i))]
        (cond
          (= c2 (chr "["))
          (if-let [f (find-index |(<= 0x40 $ 0x7E) (slice b (+ i 2)))]
            (let [end (+ i 2 f)
                  params (string (slice b (+ i 2) end))
                  final-byte (b end)]
              (cond
                (= params "200")
                (if-let [stop (string/find paste-end b end)]
                  [{:key :paste :text (string (slice b (inc end) stop))}
                   (- (+ stop (length paste-end)) i)])
                (string/has-prefix? "<" params)
                [(mouse-key params final-byte) (- (inc end) i)]
                [(csi-key params final-byte) (- (inc end) i)]))
            (if final [{:key :esc} 1]))
          (= c2 (chr "O"))
          (if (< (+ i 2) n)
            [(if-let [k (csi-letters (b (+ i 2)))] {:key k}) 3]
            (if final [{:key :esc} 1]))
          (= c2 27) [{:key :esc} 1]
          (if-let [[k used] (decode-one b (inc i) final)]
            [(if k
               (if (= :enter (k :key))
                 {:key :alt-enter}
                 (struct ;(kvs k) :alt true)))
             (inc used)]
            (if final [{:key :esc} 1])))))
    (or (< c 32) (= c 127))
    [(if (= c 127) {:key :backspace} (ctrl-key c)) 1]
    (>= c 0x80)
    (if-let [len (utf8-length c)]
      (if (<= (+ i len) n)
        [{:key :char :text (string (slice b i (+ i len)))} len]
        (if final [nil (- n i)]))
      [nil 1])
    [{:key :char :text (string/from-bytes c)} 1]))

(defn decode
  ```
  Decodes the terminal input `bytes` into keys. Returns [keys rest], with
  `rest` the bytes of a key not whole yet. When `final`, nothing more is
  coming for them: a lone escape becomes Esc, a cut character is dropped.
  A paste is waited for to its end even then.

  A key is a struct with `:key`, and `:ctrl`, `:alt`, `:shift` when held:
  `{:key :char :text "ř"}`, `{:key :up :ctrl true}`, `{:key :enter}`,
  `{:key :ctrl-enter}` (also Ctrl+J, as terminals cannot tell them apart),
  `{:key :alt-enter}`, `{:key :paste :text ...}`, `{:key :wheel :dy 1}`.
  ```
  [bytes &opt final]
  (def keys @[])
  (var i 0)
  (var rest nil)
  (while (and (< i (length bytes)) (nil? rest))
    (if-let [[k used] (decode-one bytes i final)]
      (do (if k (array/push keys k)) (+= i used))
      (set rest (slice bytes i))))
  [keys (or rest "")])

# Terminal

(defn- windows-reader
  ```
  Reads the console on a thread of its own, as rawterm's getch blocks the
  whole loop there. rawterm keeps raw mode per thread, so this thread
  begins it too; it is loaded again here, as a thread starts bare. A
  failure is given to the inbox, as nobody else hears of it.
  ```
  [[inbox syspath]]
  (setdyn :syspath syspath)
  (try
    (do
      (def rt (require "spork/rawterm"))
      ((get-in rt ['begin :value]))
      (def getch (get-in rt ['getch :value]))
      (forever
        (def b (getch @""))
        (if (pos? (length b)) (ev/give inbox [:bytes (string b)]))))
    ([err] (ev/give inbox [:error (string err)]))))

(defmacro- until-closed
  ```
  Runs `body` in a fiber on the loop until `close` cancels it. The
  cancel is its end, not a failure, so it is not left unhandled.

  The fiber answers to `term`'s own channel. Left to inherit, it would
  answer to whatever supervises the fiber opening the terminal -- inside
  a Producer, its Manager, which counts every fiber ending on its channel
  as a Producer finished, and stops waiting once the count is out.
  ```
  [term & body]
  ~(ev/go (fn []
            (try (do ,;body)
              ([err fib] (unless (= err :closed) (propagate err fib)))))
          nil (,term :supervisor)))

(def- enter-seq"\e[?1049h\e[?2004h\e[?25l\e[2J")
(def- leave-seq "\e[0m\e[?2004l\e[?1006l\e[?1000l\e[?25h\e[?1049l")
(def- mouse-seq "\e[?1000h\e[?1006h")

(defn make-screen
  "Returns a screen remembering the frame last drawn, for `frame`."
  []
  @{:last @[] :rows 0 :cols 0})

(defn frame
  ```
  Returns the output that changes the terminal from the frame last drawn
  on `screen` to `lines` in `rows` by `cols`, and remembers them. Only
  lines that changed are written. `cursor` is [row col] from zero, where
  the cursor shows, or nil to hide it.
  ```
  [screen lines cursor rows cols]
  (def out @"\e[?2026h\e[?25l")
  (def last (screen :last))
  (unless (and (= rows (screen :rows)) (= cols (screen :cols)))
    (buffer/push out "\e[2J")
    (array/clear last)
    (put screen :rows rows)
    (put screen :cols cols))
  (for r 0 rows
    # The last cell of the screen is left alone, as some consoles
    # scroll when it is written.
    (def s (fit (get lines r "") (if (= r (dec rows)) (dec cols) cols)))
    (unless (= s (get last r))
      (buffer/push out (string/format "\e[%d;1H" (inc r)) s "\e[0m\e[K")
      (put last r s)))
  (if-let [[r c] cursor]
    (buffer/push out (string/format "\e[%d;%dH\e[?25h" (inc r) (inc c))))
  (buffer/push out "\e[?2026l")
  out)

(defn terminal?
  "Returns true when stdin and stdout are a terminal `open` can take."
  []
  # Windows calls the NUL device a tty, and gives no console size for it.
  (def [rows cols] (rawterm/size))
  (and (rawterm/isatty) (< 0 rows 10000) (< 0 cols 10000)))

(defn make-input
  ```
  Returns the input side of a terminal, bound to no console: `read-keys`
  reads what is given to its `:inbox` as `[:bytes bytes]`. `open` makes
  one for the console; given bytes by hand, it reads them the same way.
  Its fibers end with `close-input`.
  ```
  [&opt opts]
  (default opts {})
  (def inbox (ev/thread-chan 1024))
  (def term @{:inbox inbox :screen (make-screen) :pending ""
              :flush 0 :fibers @[]
              :arm (ev/chan 64) :supervisor (ev/chan 8)
              :out (get opts :out stdout)})
  # Bytes of a key not whole are given a moment to arrive. One timer
  # waits it out for every such key, armed with the key's number; arming
  # it again meanwhile starts the moment over, and only the newest number
  # is flushed.
  (array/push (term :fibers)
              (until-closed term
                (def arm (term :arm))
                (forever
                  (var n (ev/take arm))
                  (ev/sleep 0.03)
                  (while (pos? (ev/count arm))
                    (while (pos? (ev/count arm)) (set n (ev/take arm)))
                    (ev/sleep 0.03))
                  (ev/give inbox [:flush n]))))
  term)

(defn close-input
  "Ends the fibers of the input `term`."
  [term]
  (each f (term :fibers) (ev/cancel f :closed)))

(defn open
  ```
  Takes the terminal: raw input, the alternate screen, bracketed paste,
  and the mouse wheel unless `:mouse` is false in `opts`. It draws on
  `:out`, stdout by default; stderr leaves stdout to the result. Returns
  the terminal, to `read-keys` from, `present` on and `close`. Errors
  when stdin is not a terminal.
  ```
  [&opt opts]
  (default opts {})
  (unless (terminal?)
    (error "gp/tui needs a terminal on stdin and stdout"))
  (def term (make-input opts))
  (def inbox (term :inbox))
  (if windows?
    (do
      (rawterm/begin)
      (ev/thread windows-reader [inbox (dyn :syspath)] :n)
      (array/push (term :fibers)
                  (until-closed term
                    (var size (rawterm/size))
                    (forever
                      (ev/sleep 0.25)
                      (def now (rawterm/size))
                      (unless (= now size)
                        (set size now)
                        (ev/give inbox [:resize ;now]))))))
    (do
      (rawterm/begin (fn [rows cols] (ev/give inbox [:resize rows cols])))
      (array/push (term :fibers)
                  (until-closed term
                    (forever
                      (ev/give inbox
                               [:bytes (string (rawterm/getch @""))]))))))
  (file/write (term :out)
              (string enter-seq (if (get opts :mouse true) mouse-seq "")))
  (file/flush (term :out))
  term)

(defn close
  ```
  Gives the terminal back as it was. On Windows the reading thread stays
  blocked on the console until the process ends.
  ```
  [term]
  (close-input term)
  (file/write (term :out) leave-seq)
  (file/flush (term :out))
  (rawterm/end))

(defmacro with-terminal
  "Runs `body` with `binding` bound to the terminal `open`ed with `opts`."
  [[binding opts] & body]
  ~(let [,binding (,open ,opts)]
     (defer (,close ,binding) ,;body)))

(defn- decode-pending [term out final]
  (def [keys rest] (decode (term :pending) final))
  (array/concat out keys)
  (put term :pending rest)
  # Bytes of a key not whole are given a moment to arrive, and then read
  # as they are: an escape alone is the Esc key.
  (when (and (not (empty? rest)) (not (string/has-prefix? paste-start rest)))
    (def n (inc (term :flush)))
    (put term :flush n)
    (def arm (term :arm))
    (if (< (ev/count arm) (ev/capacity arm)) (ev/give arm n))))

(defn read-keys
  ```
  Waits for input on `term` and returns an array of the keys read, see
  `decode`. A resize is the key `{:key :resize :rows r :cols c}`.
  ```
  [term]
  (def out @[])
  (while (empty? out)
    (match (ev/take (term :inbox))
      [:bytes b] (do (put term :pending (string (term :pending) b))
                   (decode-pending term out false))
      [:resize rows cols] (array/push out {:key :resize :rows rows :cols cols})
      [:error err] (error err)
      [:flush n] (if (= n (term :flush)) (decode-pending term out true))))
  out)

(defn size
  "Returns the terminal size as [rows cols]."
  []
  (rawterm/size))

(defn present
  "Draws `lines` on `term`, with the cursor at `cursor` or hidden."
  [term lines &opt cursor]
  (def [rows cols] (rawterm/size))
  (file/write (term :out) (frame (term :screen) lines cursor rows cols))
  (file/flush (term :out)))

(defn key-producer
  ```
  Returns a Producer that reads keys from `term` for ever and produces
  the Event `on-key` returns for each, if any.
  ```
  [term on-key]
  (producer
    (forever
      (each k (read-keys term)
        (if-let [e (on-key k)] (produce e))))))

(defn ticker
  "Returns a Producer that produces `(event-fn)` every `seconds`."
  [seconds event-fn]
  (producer
    (forever
      (ev/sleep seconds)
      (produce (event-fn)))))

# Layout

(defn stack
  ```
  Lays `blocks` out top to bottom in `rows`. A block is an indexed of
  lines, which keeps its height, or one table `{:flex lines :scroll n}`,
  which gets the rows left and shows them from line `n`. Returns a table
  of the `:lines`, and for the flex block its clamped `:scroll`, `:top`
  row and `:height`.
  ```
  [rows & blocks]
  (def fixed (sum (map |(if (table? $) 0 (length $)) blocks)))
  (def height (max 0 (- rows fixed)))
  (def res @{:lines @[] :scroll 0 :top 0 :height 0})
  (each b blocks
    (if (table? b)
      (let [lines (b :flex)
            scroll (max 0 (min (get b :scroll 0) (- (length lines) height)))]
        (merge-into res {:scroll scroll :top (length (res :lines))
                         :height height})
        (def shown (slice lines scroll (min (length lines) (+ scroll height))))
        (array/concat (res :lines) shown)
        (for _ (length shown) height (array/push (res :lines) "")))
      (array/concat (res :lines) b)))
  res)

# Editor

(defn- next-pos [text pos]
  (or (rawterm/buffer-traverse text pos 1 true) (length text)))

(defn- prev-pos [text pos]
  (if (pos? pos) (or (rawterm/buffer-traverse text pos -1 true) 0) 0))

(defn- line-start [text pos]
  (if-let [i (last (string/find-all "\n" (slice text 0 pos)))] (inc i) 0))

(defn- line-end [text pos]
  (or (string/find "\n" text pos) (length text)))

(defn- word? [text pos]
  (not (index-of (text pos) [32 10 9])))

(defn make-editor
  ```
  Returns a text editor. `opts` can have `:prompt` (a line drawn before
  the first row), `:multiline` (false makes it one line), `:max-rows`
  (rows it grows to, 10), `:submit` (keys that submit, by default
  Ctrl+Enter and Alt+Enter) and `:newline` (keys that break the line, by
  default Enter).
  ```
  [&opt opts]
  (default opts {})
  @{:text "" :cursor 0 :scroll 0 :goal nil
    :history @[] :hpos nil :draft ""
    :prompt (get opts :prompt "")
    :multiline (get opts :multiline true)
    :max-rows (get opts :max-rows 10)
    :submit (get opts :submit [:ctrl-enter :alt-enter])
    :newline (get opts :newline [:enter])})

(defn editor/text
  "Returns the text of editor `ed`."
  [ed]
  (ed :text))

(defn editor/set
  "Sets the text of editor `ed` to `text`, the cursor at its end."
  [ed text]
  (merge-into ed {:text (string text) :cursor (length text) :goal nil})
  ed)

(defn- edit [ed text cursor]
  (merge-into ed {:text (string text) :cursor cursor :goal nil :hpos nil})
  :changed)

(defn- insert [ed s]
  (def {:text t :cursor c} ed)
  (def s (if (ed :multiline) s (string/replace-all "\n" " " s)))
  (edit ed (string (slice t 0 c) s (slice t c)) (+ c (length s))))

(defn- delete-range [ed from to]
  (def t (ed :text))
  (edit ed (string (slice t 0 from) (slice t to)) from))

(defn- move [ed cursor]
  (merge-into ed {:cursor cursor :goal nil})
  :moved)

(defn- word-back [t c]
  (var p c)
  (while (and (pos? p) (not (word? t (prev-pos t p)))) (set p (prev-pos t p)))
  (while (and (pos? p) (word? t (prev-pos t p))) (set p (prev-pos t p)))
  p)

(defn- word-forward [t c]
  (var p c)
  (while (and (< p (length t)) (not (word? t p))) (set p (next-pos t p)))
  (while (and (< p (length t)) (word? t p)) (set p (next-pos t p)))
  p)

(defn- wrap-line
  "Byte ranges of the line of `text` in [start, end), each within `cols`."
  [text start end cols]
  (def ranges @[])
  (def line (slice text start end))
  (var s 0)
  (while (< s (length line))
    (var e (+ s (length (rawterm/slice-monowidth line cols s))))
    (if (= e s) (set e (next-pos line s)))
    (array/push ranges [(+ start s) (+ start e)])
    (set s e))
  (if (empty? ranges) (array/push ranges [start start]))
  ranges)

(defn- editor-rows
  "Visual rows of `ed` in `cols`, and the row and column of its cursor."
  [ed cols]
  (def {:text t :cursor c} ed)
  # A column is kept free, so the cursor has a cell after a full row.
  (def width (max 1 (- cols (line-width (ed :prompt)) 1)))
  (def rows @[])
  (var start 0)
  (forever
    (def end (line-end t start))
    (array/concat rows (wrap-line t start end width))
    (if (= end (length t)) (break))
    (set start (inc end)))
  (def row (or (find-index (fn [[s e]] (and (<= s c) (< c e))) rows)
               (find-index (fn [[_ e]] (= c e)) rows)
               0))
  [rows row (rawterm/monowidth t ((rows row) 0) c)])

(defn- pos-at-col [t [s e] col]
  (var p s)
  (var w 0)
  (while (< p e)
    (def n (next-pos t p))
    (def cw (rawterm/monowidth t p n))
    (if (> (+ w cw) col) (break))
    (+= w cw)
    (set p n))
  p)

(defn- history-move [ed dir]
  (def h (ed :history))
  (def from (or (ed :hpos) (length h)))
  (def to (+ from dir))
  (when (<= 0 to (length h))
    (if (nil? (ed :hpos)) (put ed :draft (ed :text)))
    (def text (if (= to (length h)) (ed :draft) (h to)))
    (merge-into ed {:text text :cursor (length text) :goal nil
                    :hpos (if (= to (length h)) nil to)})
    :changed))

(defn- vertical [ed dir cols]
  (def [rows row col] (editor-rows ed cols))
  (def target (+ row dir))
  (if (<= 0 target (dec (length rows)))
    (let [goal (or (ed :goal) col)]
      (put ed :cursor (pos-at-col (ed :text) (rows target) goal))
      (put ed :goal goal)
      :moved)
    (history-move ed dir)))

(defn editor/submit
  "Remembers the text of `ed` in its history and empties it."
  [ed]
  (def t (ed :text))
  (if (and (not (empty? t)) (not= t (last (ed :history))))
    (array/push (ed :history) t))
  (merge-into ed {:text "" :cursor 0 :scroll 0 :goal nil :hpos nil :draft ""})
  ed)

(defn editor/key
  ```
  Handles `key` in editor `ed`, see `decode`. `cols` is the width it is
  drawn in, for Up and Down. Returns `:changed` when the text changed,
  `:moved` when only the cursor did, `:submit` (the text is left for the
  caller, see `editor/submit`), or nil when the key is not the editor's.
  ```
  [ed key &opt cols]
  (default cols 80)
  (def {:text t :cursor c} ed)
  (def k (key :key))
  (cond
    (index-of k (ed :submit)) :submit
    (and (index-of k (ed :newline)) (ed :multiline)) (insert ed "\n")
    (= k :char) (if (key :alt)
                  (case (key :text)
                    "b" (move ed (word-back t c))
                    "f" (move ed (word-forward t c)))
                  (insert ed (key :text)))
    (= k :paste) (insert ed (string/replace-all "\r" "\n"
                                                (string/replace-all "\r\n" "\n" (key :text))))
    (= k :backspace) (if (pos? c)
                       (if (or (key :ctrl) (key :alt))
                         (delete-range ed (word-back t c) c)
                         (delete-range ed (prev-pos t c) c)))
    (or (= k :delete) (= k :ctrl-d)) (if (< c (length t))
                                       (delete-range ed c (next-pos t c)))
    (= k :left) (move ed (if (key :ctrl) (word-back t c) (prev-pos t c)))
    (= k :right) (move ed (if (key :ctrl) (word-forward t c) (next-pos t c)))
    (or (= k :home) (= k :ctrl-a)) (move ed (line-start t c))
    (or (= k :end) (= k :ctrl-e)) (move ed (line-end t c))
    (= k :ctrl-b) (move ed (prev-pos t c))
    (= k :ctrl-f) (move ed (next-pos t c))
    (= k :ctrl-w) (if (pos? c) (delete-range ed (word-back t c) c))
    (= k :ctrl-u) (delete-range ed (line-start t c) c)
    (= k :ctrl-k) (delete-range ed c (line-end t c))
    (or (= k :up) (= k :ctrl-p)) (vertical ed -1 cols)
    (or (= k :down) (= k :ctrl-n)) (vertical ed 1 cols)))

(defn editor/render
  ```
  Returns [lines cursor] of editor `ed` drawn in `cols`: at most its
  `:max-rows` lines, scrolled to the cursor, the first after the prompt
  and the others under it. `style` is the style of the text.
  ```
  [ed cols &opt style]
  (def [rows row col] (editor-rows ed cols))
  (def height (if (ed :multiline) (min (ed :max-rows) (length rows)) 1))
  (def scroll (max 0 (min (ed :scroll) row (- (length rows) height))
                   (- row (dec height))))
  (put ed :scroll scroll)
  (def indent (string/repeat " " (line-width (ed :prompt))))
  (def lines
    (seq [i :range [scroll (+ scroll height)]
          :let [[s e] (rows i)
                text (slice (ed :text) s e)]]
      [;(pieces (if (zero? i) (ed :prompt) indent))
       (if style (styled style text) text)]))
  [lines [(- row scroll) (+ (line-width (ed :prompt)) col)]])

# Chooser

(defn make-chooser
  ```
  Returns a chooser over the strings `items`, filtered by fuzzy matching
  what is typed. `opts` can have `:prompt-format`, formatted with the
  counts of the matching and of all items.
  ```
  [items &opt opts]
  (default opts {})
  (assert (indexed? items) "Items must be indexed collection.")
  @{:items items :matches items :sel 0 :scroll 0
    :prompt-format (get opts :prompt-format "%i/%i> ")
    :editor (make-editor {:multiline false :submit []})})

(defn chooser/query
  "Returns what is typed into chooser `ch`."
  [ch]
  (editor/text (ch :editor)))

(defn- refilter [ch]
  (def q (chooser/query ch))
  (put ch :matches
       (if (empty? q)
         (ch :items)
         (map first (scorer/score-n-order q (map |[$ 0] (ch :items))))))
  (merge-into ch {:sel 0 :scroll 0}))

(defn chooser/result
  "Returns the item selected in chooser `ch`, or what is typed when none."
  [ch]
  (get (ch :matches) (ch :sel) (chooser/query ch)))

(defn chooser/key
  ```
  Handles `key` in chooser `ch`. Returns `:choose` on Enter, `:cancel`
  on Esc, Ctrl+C or Ctrl+Q, `:changed` or `:moved`, or nil.
  ```
  [ch key]
  (def k (key :key))
  (def n (length (ch :matches)))
  (cond
    (index-of k [:enter :ctrl-enter :alt-enter]) :choose
    (index-of k [:esc :ctrl-c :ctrl-q]) :cancel
    (index-of k [:down :ctrl-n])
    (do (put ch :sel (min (dec n) (inc (ch :sel)))) :moved)
    (and (= k :tab) (not (key :shift)))
    (do (put ch :sel (min (dec n) (inc (ch :sel)))) :moved)
    (or (index-of k [:up :ctrl-p]) (and (= k :tab) (key :shift)))
    (do (put ch :sel (max 0 (dec (ch :sel)))) :moved)
    (= k :wheel)
    (do (put ch :sel (max 0 (min (dec n) (+ (ch :sel) (key :dy))))) :moved)
    (= :changed (editor/key (ch :editor) key))
    (do (refilter ch) :changed)))

(defn- highlighted [item q selected]
  (def marks (if (empty? q) @[] (or (scorer/positions q item) @[])))
  (def base (if selected :reverse nil))
  (def out @[])
  (var p 0)
  (while (< p (length item))
    (def n (next-pos item p))
    (def text (slice item p n))
    (array/push out
                (cond
                  (index-of p marks) (styled (if selected [:reverse :bold :green]
                                               [:bold :green]) text)
                  base (styled base text)
                  text))
    (set p n))
  out)

(defn chooser/render
  "Returns [lines cursor] of chooser `ch` drawn in `rows` by `cols`."
  [ch rows cols]
  (def ed (ch :editor))
  (def m (ch :matches))
  (put ed :prompt (string/format (ch :prompt-format) (length m)
                                 (length (ch :items))))
  (def [query cursor] (editor/render ed cols))
  (def height (max 0 (dec rows)))
  (def sel (ch :sel))
  (def scroll (max 0 (min (ch :scroll) sel) (- sel (dec height))))
  (put ch :scroll scroll)
  (def q (chooser/query ch))
  [@[;query
     ;(seq [i :range [scroll (min (length m) (+ scroll height))]]
        (highlighted (m i) q (= i sel)))]
   cursor])

(defn choose
  ```
  Takes the terminal and lets the user choose one of `items` with a
  chooser made with `opts`. Returns the chosen item, or nil when
  cancelled.
  ```
  [items &opt opts]
  (def ch (make-chooser items opts))
  (with-terminal [term opts]
    (var result nil)
    (prompt :done
      (forever
        (def [rows cols] (size))
        (present term ;(chooser/render ch rows cols))
        (each k (read-keys term)
          (case (chooser/key ch k)
            :choose (do (set result (chooser/result ch)) (return :done))
            :cancel (return :done)))))
    result))
