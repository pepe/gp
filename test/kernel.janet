(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)
(import gp/kernel)

(start-suite "Kernel documentation")
(assert-docs "gp/kernel")
(end-suite)

(kernel/defkernel saxpy
  [n:i32
   alpha:f32
   (x (buffer :f32 [n] :read))
   (y (buffer :f32 [n] :read-write))]
  (parallel [i 0 n]
    (store! y [i]
      (+ (* alpha (load x [i]))
         (load y [i])))))

(kernel/defkernel sum
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n]
      (load x [i]))))

(start-suite "Kernel frontend")

(assert (kernel/kernel? saxpy) "kernel value")
(assert (= 'saxpy (kernel/name saxpy)) "kernel name")
(assert (kernel/valid? saxpy) "valid kernel")
(assert (empty? (kernel/diagnostics saxpy)) "no diagnostics")
(assert (= :block ((kernel/ir saxpy) :op)) "normalized block")
(assert (= :parallel
           (get-in (kernel/ir saxpy) [:statements 0 :op]))
        "normalized parallel loop")
(assert (= :f32
           (get-in (kernel/parameters saxpy) [1 :dtype]))
        "normalized scalar dtype")
(assert (= :read-write
           (get-in (kernel/parameters saxpy) [3 :access]))
        "normalized buffer access")

(def outside-index :untouched)
(kernel/defkernel hygiene
  [n:i32 (output (buffer :i32 [n] :write))]
  (parallel [outside-index 0 n]
    (store! output [outside-index] outside-index)))
(assert (= :untouched outside-index) "macro does not capture loop names")

(def invalid-form
  '(kernel/defkernel unsafe
     [n:i32
      n:i32
      (source (buffer :f32 [n] :write))
      (target (buffer :f32 [n] :read))]
     (parallel [i 0 n]
       (store! target [0] (load source [i])))))
(def lint-environment (table/clone (curenv)))
(def lints @[])
(compile invalid-form lint-environment :anonymous lints)
(def lint-messages (map last lints))
(assert (find |(string/find "duplicate kernel parameter" $)
              lint-messages)
        "duplicate parameter lint")
(assert (find |(string/find "write-only buffer" $)
              lint-messages)
        "buffer access lint")
(assert (find |(string/find "read-only buffer" $)
              lint-messages)
        "store access lint")
(assert (find |(string/find "exact parallel indexes" $)
              lint-messages)
        "parallel safety lint")
(assert (all |(= :strict (get $ 0)) lints) "strict lint levels")
(assert (all |(and (number? (get $ 1))
                   (number? (get $ 2)))
             lints)
        "lint source locations")

(def dtype-lints @[])
(compile
  '(kernel/defkernel mixed-dtypes
     [n:i32
      alpha:f64
      (x (buffer :f32 [n] :read))
      (y (buffer :f32 [n] :write))]
     (parallel [i 0 n]
       (store! y [i] (* alpha (load x [i])))))
  (table/clone (curenv)) :anonymous dtype-lints)
(assert (find |(string/find "incompatible dtypes" $)
              (map last dtype-lints))
        "mixed arithmetic dtype lint")

(def shadow-lints @[])
(compile
  '(kernel/defkernel shadowed
     [i:i32 (output (buffer :i32 [1] :write))]
     (parallel [i 0 1]
       (store! output [i] i)))
  (table/clone (curenv)) :anonymous shadow-lints)
(assert (find |(string/find "shadows an existing binding" $)
              (map last shadow-lints))
        "loop shadowing lint")

(def malformed-lints @[])
(assert-no-error
  "malformed kernel is linted without crashing the frontend"
  (compile
    '(kernel/defkernel malformed not-parameters
       (parallel not-a-binding)
       (store!))
    (table/clone (curenv)) :anonymous malformed-lints))
(assert (find |(string/find "parameters must use brackets" $)
              (map last malformed-lints))
        "malformed parameters lint")
(assert (find |(string/find "binding must be" $)
              (map last malformed-lints))
        "malformed loop lint")
(assert (find |(string/find "store! is" $)
              (map last malformed-lints))
        "malformed store lint")

(def invalid-expansion (macex1 invalid-form))
(def invalid-kernel (get-in invalid-expansion [2 1]))
(assert (kernel/kernel? invalid-kernel) "invalid kernel remains inspectable")
(assert (not (kernel/valid? invalid-kernel)) "invalid kernel cannot run")
(assert-error "invalid kernel rejected"
              (kernel/run! invalid-kernel {}))

(def macro-entry (get (curenv) 'kernel/defkernel))
(assert (get macro-entry :flycheck) "defkernel participates in flycheck")

(end-suite)

(start-suite "Kernel C++ reference evaluation")

(def engine (cpp/engine))
(def x (compute/vector engine :f32 [1 2 3]))
(def y (compute/vector engine :f32 [10 20 30]))
(def bindings {:n 3 :alpha 2 :x x :y y})
(assert (= bindings (kernel/run! saxpy bindings))
        "run returns bindings")
(assert (deep= @[12 24 36] (compute/to-array y))
        "saxpy reference result")

(def result (compute/alloc engine :f32 [1]))
(kernel/run! sum {:n 3 :x x :result result})
(assert (deep= @[6] (compute/to-array result))
        "reduction reference result")

(def indices (compute/alloc engine :i32 [4]))
(kernel/run! hygiene {:n 4 :output indices})
(assert (deep= @[0 1 2 3] (compute/to-array indices))
        "parallel indexes")

(assert-error "missing scalar binding"
              (kernel/run! saxpy {:alpha 2 :x x :y y}))
(assert-error "scalar dtype validation"
              (kernel/run! saxpy {:n 1.5 :alpha 2 :x x :y y}))
(assert-error "buffer shape validation"
              (kernel/run! saxpy {:n 2 :alpha 2 :x x :y y}))
(assert-error "buffer dtype validation"
              (kernel/run! hygiene
                {:n 3 :output (compute/alloc engine :f32 [3])}))
(assert-error "writable buffer aliasing"
              (kernel/run! saxpy {:n 3 :alpha 2 :x y :y y}))

(end-suite)
