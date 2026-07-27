(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)
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

(kernel/defkernel matrix-copy
  [rows:i32
   columns:i32
   (input (buffer :f32 [rows columns] :read))
   (output (buffer :f32 [rows columns] :write))]
  (parallel [row 0 rows]
    (parallel [column 0 columns]
      (store! output [row column]
        (load input [row column])))))

(start-suite "Kernel OpenCL lowering")

(assert (nil? (get (require "gp/compute") 'compile-kernel))
        "raw compilation is absent from public compute")

(def saxpy-source (kernel/opencl-source saxpy))
(assert (string/find "__kernel void gp_kernel_saxpy" saxpy-source)
        "stable entry name")
(assert (string/find "__global const float *gp_p_x_data" saxpy-source)
        "read buffer is const")
(assert (string/find "gp_p_y_stride0" saxpy-source)
        "view strides are explicit arguments")
(assert (= saxpy-source (kernel/opencl-source saxpy))
        "source generation is deterministic")
(assert (string/find "get_global_id(1)"
                     (kernel/opencl-source matrix-copy))
        "nested parallel axes map to launch dimensions")

(def sum-source (kernel/opencl-source sum))
(assert (string/find "gp_reduce_0" sum-source)
        "reduction has an explicit accumulator")
(assert (string/find "for (int gp_i_i" sum-source)
        "reduction has an explicit serial loop")

(kernel/defkernel inconsistent-domains
  [n:i32 (output (buffer :i32 [n] :write))]
  (parallel [i 0 n]
    (store! output [i] i))
  (parallel [j 1 n]
    (store! output [j] j)))
(assert-error "inconsistent launch geometry rejected"
              (kernel/opencl-source inconsistent-domains))

(end-suite)

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

(when (opencl/available?)
  (start-suite "Kernel OpenCL execution")

  (def device-engine (opencl/engine))
  (def device-queue (compute/queue device-engine))
  (def device-x (compute/vector device-engine :f32 [1 2 3 4 5]))
  (def device-y (compute/vector device-engine :f32 [10 20 30 40 50]))
  (def device-kernel (kernel/compile device-engine saxpy))

  (assert (kernel/compiled? device-kernel) "compiled kernel metadata")
  (assert (= (kernel/source device-kernel) saxpy-source)
          "compiled source remains inspectable")
  (assert (= (kernel/cache-key device-kernel)
             (kernel/cache-key
               (kernel/compile device-engine saxpy)))
          "cache identity is deterministic")

  (def x-slice (compute/slice device-x 1 3))
  (def y-slice (compute/slice device-y 1 3))
  (def ready (compute/enqueue-fill! device-queue y-slice 5))
  (def launched
    (kernel/launch
      device-kernel device-queue
      {:n 3 :alpha 2 :x x-slice :y y-slice}
      ready))
  (compute/wait launched)
  (assert (deep= @[10 9 11 13 50] (compute/to-array device-y))
          "compiled launch honors offsets, strides, and dependencies")

  (def device-result (compute/alloc device-engine :f32 [1]))
  (def sum-kernel (kernel/compile device-engine sum))
  (compute/wait
    (kernel/launch sum-kernel device-queue
                   {:n 5 :x device-x :result device-result}))
  (assert (deep= @[15] (compute/to-array device-result))
          "reduction matches reference semantics")

  (def device-matrix
    (compute/matrix device-engine :f32 [2 3] [1 2 3 4 5 6]))
  (def copied-matrix (compute/alloc device-engine :f32 [2 3]))
  (def matrix-kernel (kernel/compile device-engine matrix-copy))
  (compute/wait
    (kernel/launch matrix-kernel device-queue
                   {:rows 2 :columns 3
                    :input device-matrix :output copied-matrix}))
  (assert (deep= @[1 2 3 4 5 6] (compute/to-array copied-matrix))
          "nested parallel launch")

  (def empty-x (compute/alloc device-engine :f32 [0]))
  (def empty-y (compute/alloc device-engine :f32 [0]))
  (def empty-event
    (kernel/launch device-kernel device-queue
                   {:n 0 :alpha 2 :x empty-x :y empty-y}))
  (assert (compute/event-complete? empty-event)
          "empty launch produces a completed event")

  (def retained-queue (compute/queue device-engine))
  (def retained-x (compute/vector device-engine :f32 [2]))
  (def retained-y (compute/vector device-engine :f32 [3]))
  (def retained-kernel (kernel/compile device-engine saxpy))
  (compute/close-engine device-engine)
  (compute/wait
    (kernel/launch retained-kernel retained-queue
                   {:n 1 :alpha 4 :x retained-x :y retained-y}))
  (assert (deep= @[11] (compute/to-array retained-y))
          "kernel, queue, and views retain the engine")
  (kernel/close retained-kernel)
  (assert (kernel/closed? retained-kernel) "explicit kernel close")
  (assert-error "closed kernel launch rejected"
                (kernel/launch retained-kernel retained-queue
                               {:n 1 :alpha 4
                                :x retained-x :y retained-y}))

  (end-suite))

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

(start-suite "Kernel math functions (kernel-0.1)")

(kernel/defkernel absolute-sum
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel absolute-peak
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce max 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel soft-evidence
  [a:f32 b:f32 (out (buffer :f32 [1] :write))]
  (store! out [0] (log (+ (exp a) (exp b)))))

(kernel/defkernel pick-larger
  [a:f32 b:f32 (out (buffer :f32 [1] :write))]
  (store! out [0] (max a b)))

(assert (string/find "fabs(" (kernel/opencl-source absolute-sum))
        "abs lowers to fabs")
(assert (string/find "= fmax(gp_reduce" (kernel/opencl-source absolute-peak))
        "max reduction lowers to an fmax accumulator")
(assert (string/find "log(" (kernel/opencl-source soft-evidence))
        "log lowers to the builtin")
(assert (string/find "exp(" (kernel/opencl-source soft-evidence))
        "exp lowers to the builtin")

(def math-x (compute/vector engine :f32 [3 -4 5]))
(def math-result (compute/alloc engine :f32 [1]))
(kernel/run! absolute-sum {:n 3 :x math-x :result math-result})
(assert (deep= @[12] (compute/to-array math-result))
        "absolute sum reference result")
(kernel/run! absolute-peak {:n 3 :x math-x :result math-result})
(assert (deep= @[5] (compute/to-array math-result))
        "absolute peak reference result")
(kernel/run! pick-larger {:a math/nan :b 3 :out math-result})
(assert (deep= @[3] (compute/to-array math-result))
        "max drops a NaN operand, pinned to fmax semantics")
(kernel/run! soft-evidence
             {:a (math/log 2) :b (math/log 3) :out math-result})
(assert (< (math/abs (- (math/log 5) (compute/get math-result 0))) 1e-6)
        "log-sum-exp reference result")

(kernel/defkernel wrong-arity
  [a:f32 (out (buffer :f32 [1] :write))]
  (store! out [0] (abs a a)))
(assert-error "math function arity is checked"
              (kernel/opencl-source wrong-arity))
(kernel/defkernel integer-abs
  [n:i32 (x (buffer :i32 [n] :read)) (out (buffer :i32 [n] :write))]
  (parallel [i 0 n] (store! out [i] (abs (load x [i])))))
(assert-error "math functions are float-only"
              (kernel/opencl-source integer-abs))
(kernel/defkernel integer-peak
  [n:i32 (x (buffer :i32 [n] :read)) (out (buffer :i32 [1] :write))]
  (store! out [0] (reduce max 0 [i 0 n] (load x [i]))))
(assert-error "math reductions are float-only"
              (kernel/opencl-source integer-peak))
(kernel/defkernel not-admitted
  [a:f32 (out (buffer :f32 [1] :write))]
  (store! out [0] (sqrt a)))
(assert-error "functions outside the admitted set stay rejected"
              (kernel/opencl-source not-admitted))

(when (opencl/available?)
  (def math-engine (opencl/engine))
  (def math-queue (compute/queue math-engine))
  (def device-values (compute/vector math-engine :f32 [3 -4 5]))
  (def device-out (compute/alloc math-engine :f32 [1]))
  (compute/wait
    (kernel/launch (kernel/compile math-engine absolute-sum) math-queue
                   {:n 3 :x device-values :result device-out}))
  (assert (deep= @[12] (compute/to-array device-out))
          "device absolute sum matches the reference")
  (compute/wait
    (kernel/launch (kernel/compile math-engine absolute-peak) math-queue
                   {:n 3 :x device-values :result device-out}))
  (assert (deep= @[5] (compute/to-array device-out))
          "device absolute peak matches the reference")
  (compute/wait
    (kernel/launch (kernel/compile math-engine soft-evidence) math-queue
                   {:a (math/log 2) :b (math/log 3) :out device-out}))
  (assert (< (math/abs (- (math/log 5) (compute/get device-out 0))) 1e-6)
          "device log-sum-exp matches the reference"))

(end-suite)
