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

