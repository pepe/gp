(import spork/sh)
(import spork/misc)
# TODO test
(defmacro fprotect
  ```
  Similar to core library `protect`. Evaluate expressions `body`, while
  capturing any errors. Evaluates to a tuple of two elements. The first
  element is true if successful, false if an error. The second is the return
  value or the fiber that errored respectively. 
  Use it, when you want to get the stacktrace of the error.
  ```
  [& body]
  (with-syms [fib res err?]
    ~(let [,fib (,fiber/new (fn [] ,;body) :ie)
           ,res (,resume ,fib)
           ,err? (,= :error (,fiber/status ,fib))]
       [(,not ,err?) (if ,err? ,fib ,res)])))

(defmacro first-capture
  "Returns first match in string `s` by the peg `p`"
  [p s]
  ~(first (peg/match ,p ,s)))

(defn union
  "Returns the union of the the members of the sets."
  [& sets]
  (def head (first sets))
  (def ss (array ;sets))
  (while (not= 1 (length ss))
    (let [aset (array/pop ss)]
      (each i aset
        (if-not (find-index |(= i $) head) (array/push head i)))))
  (first ss))

(defn intersect
  "Returns the intersection of the the members of the sets."
  [& sets]
  (def ss (array ;sets))
  (while (not= 1 (length ss))
    (let [head (first ss)
          aset (array/pop ss)]
      (put ss 0 (filter (fn [i] (find-index |(deep= i $) aset)) head))))
  (first ss))

(def peg-grammar
  "Custom peg grammar with crlf and to end."
  (merge (dyn :peg-grammar)
         ~{:crlf "\r\n"
           :cap-to-crlf (* '(to :crlf) :crlf)
           :toe '(to -1)
           :boundaries (+ :s (set ",.?!_-/|\\"))
           :split (any (+ :boundaries '(some :a)))}))

(defn setup-peg-grammar
  "Merges `peg-grammar` into `:peg-grammar` `dyn`"
  []
  (setdyn :peg-grammar peg-grammar))

(defn named-capture
  ```
  Creates group where the first member is keyword `name`
  and other members are `captures`.
  ```
  [name & captures]
  ~(group (* (constant ,(keyword name)) ,;captures)))

(def <-: "Alias for named-capture." named-capture)

(defmacro one-of
  ```
  Takes value `v` and variadic number of values in `ds`,
  and returns the `v` if it is present in the `ds`.
  ```
  [v & ds]
  ~(or ,;(seq [i :in ds] ~(= ,v ,i))))

(defmacro define
  "Define symbol from dyn under `key`."
  [key]
  (assert (keyword? key))
  ~(def ,(symbol key) (dyn ,key)))

(defn ev/drain
  "Drains a `chan`."
  [chan]
  (while (> (ev/count chan) 0) (ev/take chan)))

(defn watch-spawn
  ```
  Spawns commands on `$PATH` and watch the project files. 

  Argument `matcher` should be a peg to match file name,
  if it matches it, then the `cmds` are executed.

  Optional `wait?` argument makes watcher wait for the process to finish,
  when truthy.

  Optional `env` can contain environment variables table for the process.
  Defaults to `(os/environ)`.
  ```
  [matcher cmds &opt wait? env]
  (default env (os/environ))
  (def ch (ev/chan 9))
  (def fw (filewatch/new ch))
  (def mp (peg/compile ~{:matcher ,matcher :main (<- :matcher)}))
  (defn spawnenv []
    (os/spawn cmds :pe env))
  (var ps (spawnenv))
  (filewatch/add fw "./" :last-write :recursive) # TODO check linux
  (if wait? (os/proc-wait ps))
  (filewatch/listen fw)
  (forever (def e (ev/take ch))
    (when-let [[fnm] (peg/match mp (e :file-name))]
      (eprintf "File %s modified, restarting" fnm)
      (if-not wait? (os/proc-kill ps))
      (set ps (spawnenv))
      (if wait? (os/proc-wait ps))
      (ev/drain ch))))

(defn script
  "On windows you have to add .bat"
  [s]
  (misc/cond-> s (= (os/which) :windows) (string ".bat")))

(defn executable
  "On windows you have to add .exe"
  [s]
  (misc/cond-> s (= (os/which) :windows) (string ".exe")))

(defn precise-time
  ```
  Returns precise time `t` with s, ms, us, ns precision
  as a string.
  ```
  [t]
  (string/format
    ;(cond
       (zero? t) ["0s"]
       (>= t 1) ["%.3fs" t]
       (>= t 1e-3) ["%.3fms" (* t 1e3)]
       (>= t 1e-6) ["%.3fus" (* t 1e6)]
       (>= t 1e-9) ["%.3fns" (* t 1e9)])))

(defn first-line
  "Returns first line of the `text`"
  [text]
  (string/slice text 0 (string/find "\n" text)))

(def alph
  "Radix alphabet"
  "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

(defn to-radix
  "Convert number to radix, which defaults to max 36"
  [n &opt radix]
  (default radix (length alph))
  (def b @"")
  (var rem n)
  (while (pos? rem)
    (buffer/push-byte b (alph (mod rem radix)))
    (set rem (div rem radix)))
  (reverse b))

(defn ssh-cmds
  "Returns tuple for `os/execute` to call ssh on `host` with `cmds`"
  [host & cmds]
  (as-> cmds cs
        (map (fn [c] (string/join c " ")) cs)
        (string/join cs " && ")
        (tuple "ssh" host cs)))
