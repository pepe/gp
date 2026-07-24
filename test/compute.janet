(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)

(defn capability-sweep
  "Attempt every declared operation for every dtype and execution mode and
  assert each outcome matches the capability table."
  [engine]
  (def host (cpp/engine))
  (def queue (compute/queue engine))
  (defn check [execution operation dtype thunk]
    (def [ok _] (protect (thunk)))
    (assert (= (compute/supports? engine operation dtype execution) ok)
            (string/format "capability sweep %v %v %v"
                           execution operation dtype)))
  (each dtype [:f32 :f64 :i32]
    (check :synchronous :alloc dtype |(compute/alloc engine dtype [2]))
    (check :synchronous :transfer dtype
           |(compute/transfer engine (compute/vector host dtype [1 2])))
    (def [allocated x] (protect (compute/vector engine dtype [1 2])))
    (if allocated
      (do
        (def y (compute/vector engine dtype [3 4]))
        (def a (compute/matrix engine dtype [2 2] [1 2 3 4]))
        (def b (compute/matrix engine dtype [2 2] [5 6 7 8]))
        (check :synchronous :get dtype |(compute/get x 0))
        (check :synchronous :put dtype |(compute/put! x 0 1))
        (check :synchronous :fill dtype |(compute/fill! x 1))
        (check :synchronous :copy dtype |(compute/copy! y x))
        (check :synchronous :scal dtype |(compute/scal! x 2))
        (check :synchronous :axpy dtype |(compute/axpy! y 2 x))
        (check :synchronous :dot dtype |(compute/dot x y))
        (check :synchronous :mm dtype |(compute/mm a b))
        (check :queued :fill dtype
               |(compute/wait (compute/enqueue-fill! queue x 1)))
        (check :queued :copy dtype
               |(compute/wait (compute/enqueue-copy! queue y x)))
        (check :queued :scal dtype
               |(compute/wait (compute/enqueue-scal! queue x 2)))
        (check :queued :axpy dtype
               |(compute/wait (compute/enqueue-axpy! queue y 2 x)))
        (check :queued :dot dtype
               |(let [[_ event] (compute/enqueue-dot queue x y)]
                  (compute/wait event)))
        (check :queued :mm dtype
               |(let [[_ event] (compute/enqueue-mm queue a b)]
                  (compute/wait event))))
      (each [execution operations]
            (pairs {:synchronous [:get :put :fill :copy :scal :axpy :dot :mm]
                    :queued [:fill :copy :scal :axpy :dot :mm]})
        (each operation operations
          (assert (not (compute/supports? engine operation dtype execution))
                  (string/format "capability sweep %v %v %v"
                                 execution operation dtype))))))
  (compute/close-queue queue))

(start-suite "Compute documentation")
(assert-docs "gp/compute")
(assert-docs "gp/compute/cpp")
(assert-docs "gp/compute/opencl")
(end-suite)

(when (opencl/available?)
  (start-suite "Compute OpenCL discovery")

  (def available-devices (opencl/devices))
  (assert (> (length available-devices) 0) "OpenCL device")
  (def device (first available-devices))
  (assert (string? (device :name)) "device name")
  (assert (string? (device :vendor)) "device vendor")
  (assert (string? (device :version)) "device version")
  (assert (> (device :global-memory) 0) "device memory")

  (var gpu
    (opencl/engine :platform (device :platform) :device (device :index)))
  (assert (= "opencl" (compute/engine-name gpu)) "OpenCL engine")
  (assert (= (device :name) (compute/engine-device-name gpu)) "engine device")
  (assert (compute/sync gpu) "OpenCL synchronization")
  (def opencl-capabilities (compute/capabilities gpu))
  (assert (= :compute-0 (opencl-capabilities :contract))
          "OpenCL compute contract")
  (assert (= :opencl (opencl-capabilities :backend))
          "OpenCL capability backend")
  (assert (compute/supports? gpu :fill :i32)
          "OpenCL integer storage operation")
  (assert (not (compute/supports? gpu :dot :i32))
          "OpenCL integer numerical policy is explicit")
  (assert (= (device :fp64?)
             (compute/supports? gpu :dot :f64 :queued))
          "OpenCL f64 capability belongs to the device")
  (assert (= opencl-capabilities (compute/capabilities gpu))
          "OpenCL capability contract is cached")
  (capability-sweep gpu)

  (end-suite)

  (start-suite "Compute OpenCL transfer and views")

  (def cpu (cpp/engine))
  (def host-vector (compute/vector cpu :f32 [1 2 3 4]))
  (def gpu-vector (compute/transfer gpu host-vector))
  (assert (= :f32 (compute/dtype gpu-vector)) "transferred dtype")
  (assert (deep= @[4] (compute/shape gpu-vector)) "transferred shape")
  (assert (deep= @[1 2 3 4] (compute/to-array gpu-vector))
          "host to device transfer")
  (assert-error "copy never transfers implicitly"
                (compute/copy! host-vector gpu-vector))

  (def gpu-slice (compute/slice gpu-vector 1 2))
  (assert (= (compute/storage-id gpu-vector) (compute/storage-id gpu-slice))
          "OpenCL slice shares storage")
  (compute/fill! gpu-slice 9)
  (assert (deep= @[1 9 9 4] (compute/to-array gpu-vector))
          "OpenCL slice mutation")

  (def round-trip (compute/transfer cpu gpu-vector))
  (assert (deep= @[1 9 9 4] (compute/to-array round-trip))
          "device to host transfer")
  (compute/close-engine gpu)
  (assert (compute/engine-closed? gpu) "OpenCL handle closed")
  (assert (deep= @[1 9 9 4] (compute/to-array gpu-vector))
          "OpenCL view retains closed engine")
  (set gpu (compute/engine gpu-vector))

  (end-suite)

  (start-suite "Compute OpenCL operations")

  (def x (compute/vector gpu :f32 [1 2 3]))
  (def y (compute/vector gpu :f32 [4 5 6]))
  (assert (= 32 (compute/dot x y)) "OpenCL dot")
  (compute/scal! x 2)
  (assert (deep= @[2 4 6] (compute/to-array x)) "OpenCL scal")
  (compute/axpy! y 0.5 x)
  (assert (deep= @[5 7 9] (compute/to-array y)) "OpenCL axpy")

  (def overlap (compute/vector gpu :f32 [1 2 3 4]))
  (compute/copy! (compute/slice overlap 1 3)
                 (compute/slice overlap 0 3))
  (assert (deep= @[1 1 2 3] (compute/to-array overlap))
          "OpenCL overlapping copy")
  (compute/axpy! (compute/slice overlap 1 3) 1
                 (compute/slice overlap 0 3))
  (assert (deep= @[1 2 3 5] (compute/to-array overlap))
          "OpenCL overlapping axpy")

  (def ga (compute/matrix gpu :f32 [2 3] [1 2 3 4 5 6]))
  (def gb (compute/matrix gpu :f32 [3 2] [7 8 9 10 11 12]))
  (assert (deep= @[58 64 139 154] (compute/to-array (compute/mm ga gb)))
          "OpenCL matrix multiplication")
  (assert
    (deep= @[17 22 27 22 29 36 27 36 45]
           (compute/to-array (compute/mm (compute/transpose ga) ga)))
    "OpenCL strided matrix multiplication")

  (def integers (compute/vector gpu :i32 [1 2 3]))
  (compute/fill! integers 7)
  (assert (deep= @[7 7 7] (compute/to-array integers)) "OpenCL i32 fill")
  (assert-error "OpenCL i32 numerical policy" (compute/scal! integers 2))

  (when (device :fp64?)
    (def doubles (compute/vector gpu :f64 [1 2 3]))
    (assert (= 14 (compute/dot doubles doubles)) "OpenCL f64"))

  (loop [i :range [0 100]]
    (def owner (compute/vector gpu :f32 [i (+ i 1)]))
    (def retained (compute/slice owner 1 1))
    (compute/close owner)
    (assert (= (+ i 1) (compute/get retained 0)) "OpenCL retained storage"))
  (gccollect)

  (end-suite)

  (start-suite "Compute OpenCL queues and events")

  (def queued (compute/vector gpu :f32 [1 2 3]))
  (def opencl-queue (compute/queue gpu))
  (def first-fill (compute/enqueue-fill! opencl-queue queued 7))
  (def second-fill
    (compute/enqueue-fill! opencl-queue queued 9 first-fill))
  (assert (boolean? (compute/event-complete? second-fill))
          "event completion query")
  (compute/close-queue opencl-queue)
  (assert (compute/queue-closed? opencl-queue) "queue closes")
  (compute/wait second-fill)
  (assert (compute/event-complete? second-fill) "event completes")
  (assert (deep= @[9 9 9] (compute/to-array queued))
          "dependent queued fills")

  (def queued-source (compute/vector gpu :f32 [1 2 3]))
  (def queued-destination (compute/alloc gpu :f32 [3]))
  (def source-queue (compute/queue gpu))
  (def copy-queue (compute/queue gpu))
  (def source-ready
    (compute/enqueue-fill! source-queue queued-source 8))
  (def copy-complete
    (compute/enqueue-copy!
      copy-queue queued-destination queued-source source-ready))
  (compute/wait copy-complete)
  (assert (deep= @[8 8 8] (compute/to-array queued-destination))
          "dependent queued copy")

  (def queued-overlap (compute/vector gpu :f32 [1 2 3 4]))
  (compute/wait
    (compute/enqueue-copy!
      copy-queue
      (compute/slice queued-overlap 1 3)
      (compute/slice queued-overlap 0 3)))
  (assert (deep= @[1 1 2 3] (compute/to-array queued-overlap))
          "queued copy preserves overlap semantics")

  (def numerical-source (compute/vector gpu :f32 [1 2 3]))
  (def numerical-target (compute/vector gpu :f32 [4 5 6]))
  (def numerical-queue (compute/queue gpu))
  (def source-filled
    (compute/enqueue-fill! source-queue numerical-source 2))
  (def source-scaled
    (compute/enqueue-scal! numerical-queue numerical-source 3 source-filled))
  (def target-updated
    (compute/enqueue-axpy!
      copy-queue numerical-target 0.5 numerical-source source-scaled))
  (def [dot-result dot-complete]
    (compute/enqueue-dot
      numerical-queue numerical-source numerical-target target-updated))
  (compute/wait dot-complete)
  (assert (deep= @[6 6 6] (compute/to-array numerical-source))
          "dependent queued scal")
  (assert (deep= @[7 8 9] (compute/to-array numerical-target))
          "cross-queue dependent axpy")
  (assert (deep= @[144] (compute/to-array dot-result))
          "queued dot stays in native storage")

  (def queued-overlap-axpy (compute/vector gpu :f32 [1 2 3 4]))
  (compute/wait
    (compute/enqueue-axpy!
      numerical-queue
      (compute/slice queued-overlap-axpy 1 3) 1
      (compute/slice queued-overlap-axpy 0 3)))
  (assert (deep= @[1 3 5 7] (compute/to-array queued-overlap-axpy))
          "queued axpy preserves overlap semantics")

  (def queued-a (compute/matrix gpu :f32 [2 3] [1 2 3 4 5 6]))
  (def queued-b (compute/matrix gpu :f32 [3 2] [7 8 9 10 11 12]))
  (def [queued-product product-complete]
    (compute/enqueue-mm numerical-queue queued-a queued-b))
  (compute/wait product-complete)
  (assert (deep= @[58 64 139 154] (compute/to-array queued-product))
          "queued matrix multiplication")

  (compute/close-event first-fill)
  (assert (compute/event-closed? first-fill) "event closes")
  (assert-error "closed dependency"
                (compute/enqueue-fill!
                  (compute/queue gpu) queued 1 first-fill))

  (def foreign-queue (compute/queue (cpp/engine)))
  (assert-error "queue never changes engines implicitly"
                (compute/enqueue-fill! foreign-queue queued 1))

  (def lifetime-view (compute/vector gpu :f32 [1 2 3]))
  (def lifetime-queue (compute/queue gpu))
  (def lifetime-event
    (compute/enqueue-fill! lifetime-queue lifetime-view 4))
  (def lifetime-a (compute/matrix gpu :f32 [1 2] [2 3]))
  (def lifetime-b (compute/matrix gpu :f32 [2 1] [4 5]))
  (def [lifetime-result lifetime-product]
    (compute/enqueue-mm lifetime-queue lifetime-a lifetime-b lifetime-event))
  (compute/close lifetime-view)
  (compute/close lifetime-a)
  (compute/close lifetime-b)
  (compute/close-queue lifetime-queue)
  (compute/close-engine gpu)
  (compute/wait lifetime-product)
  (assert (compute/event-complete? lifetime-product)
          "result event retains engine after inputs, queue, and handle close")
  (assert (deep= @[23] (compute/to-array lifetime-result))
          "queued result retains storage after its inputs close")

  (end-suite))

(start-suite "Compute C++ engine")

(def engine (cpp/engine))
(assert (= "cpp" (compute/engine-name engine)) "engine name")
(assert (compute/sync engine) "synchronous engine")
(def cpp-capabilities (compute/capabilities engine))
(assert (= :compute-0 (cpp-capabilities :contract))
        "C++ compute contract")
(assert (= :cpp (cpp-capabilities :backend))
        "C++ capability backend")
(assert-error "capability contract is immutable"
              (put cpp-capabilities :backend :changed))
(assert (compute/supports? engine :mm :i32)
        "C++ integer numerical oracle")
(assert (compute/supports? engine :dot :f64 :queued)
        "C++ queued capability")
(assert-error "invalid capability execution"
              (compute/supports? engine :dot :f32 :later))
(assert (= cpp-capabilities (compute/capabilities engine))
        "C++ capability contract is cached")
(capability-sweep engine)

(def cpp-queue (compute/queue engine))
(def cpp-queued (compute/vector engine :f32 [1 2]))
(def cpp-event (compute/enqueue-fill! cpp-queue cpp-queued 3))
(assert (compute/event-complete? cpp-event) "C++ event completes immediately")
(assert (deep= @[3 3] (compute/to-array cpp-queued)) "C++ queued fill")
(def cpp-copy-target (compute/alloc engine :f32 [2]))
(def cpp-copy-event
  (compute/enqueue-copy! cpp-queue cpp-copy-target cpp-queued cpp-event))
(assert (compute/event-complete? cpp-copy-event) "C++ copy event completes")
(assert (deep= @[3 3] (compute/to-array cpp-copy-target)) "C++ queued copy")
(def cpp-scal-event
  (compute/enqueue-scal! cpp-queue cpp-queued 2 cpp-copy-event))
(assert (compute/event-complete? cpp-scal-event) "C++ scal event completes")
(assert (deep= @[6 6] (compute/to-array cpp-queued)) "C++ queued scal")
(def cpp-axpy-event
  (compute/enqueue-axpy!
    cpp-queue cpp-copy-target 0.5 cpp-queued cpp-scal-event))
(assert (compute/event-complete? cpp-axpy-event) "C++ axpy event completes")
(assert (deep= @[6 6] (compute/to-array cpp-copy-target)) "C++ queued axpy")
(def [cpp-dot-result cpp-dot-event]
  (compute/enqueue-dot
    cpp-queue cpp-queued cpp-copy-target cpp-axpy-event))
(assert (compute/event-complete? cpp-dot-event) "C++ dot event completes")
(assert (deep= @[72] (compute/to-array cpp-dot-result))
        "C++ queued dot result")
(def cpp-a (compute/matrix engine :f32 [1 2] [2 3]))
(def cpp-b (compute/matrix engine :f32 [2 1] [4 5]))
(def [cpp-product cpp-product-event]
  (compute/enqueue-mm cpp-queue cpp-a cpp-b cpp-dot-event))
(assert (compute/event-complete? cpp-product-event) "C++ mm event completes")
(assert (deep= @[23] (compute/to-array cpp-product))
        "C++ queued matrix multiplication")
(assert (compute/finish cpp-queue) "C++ queue finish")

(def vector (compute/vector engine :f32 [1 2 3 4]))
(assert (= :f32 (compute/dtype vector)) "dtype")
(assert (= 1 (compute/rank vector)) "rank")
(assert (deep= @[4] (compute/shape vector)) "shape")
(assert (deep= @[1] (compute/strides vector)) "strides")
(assert (= 4 (compute/count vector)) "count")
(assert (deep= @[1 2 3 4] (compute/to-array vector)) "values")
(assert (= "cpp" (compute/engine-name (compute/engine vector))) "view engine")

(compute/put! vector 1 7)
(assert (= 7 (compute/get vector 1)) "indexed mutation")
(assert-error "negative logical index" (compute/get vector -1))
(assert-error "large logical index" (compute/get vector 99))

(def zeroes (compute/alloc engine :f64 [2 2]))
(assert (deep= @[0 0 0 0] (compute/to-array zeroes)) "zero initialization")
(assert-error "unsupported dtype" (compute/alloc engine :u8 [1]))
(assert-error "value count" (compute/from-array engine :f32 [2] [1]))
(assert-error "i32 representation" (compute/vector engine :i32 [1 1.5]))
(assert-error "empty values still checked" (compute/from-array engine :f32 [1] []))
(assert-error "matrix rank" (compute/matrix engine :f32 [2] [1 2]))
(assert-error "shape dimensions are integers" (compute/alloc engine :f32 [1.5]))
(assert-error "values are numbers" (compute/vector engine :f32 [1 :two]))

(end-suite)

(start-suite "Compute retained views")

(def parent (compute/vector engine :f32 [1 2 3 4]))
(def child (compute/slice parent 1 2))
(assert (= (compute/storage-id parent) (compute/storage-id child))
        "slice shares storage")
(compute/fill! child 9)
(assert (deep= @[1 9 9 4] (compute/to-array parent)) "slice mutates parent")
(compute/close parent)
(assert (compute/closed? parent) "parent closed")
(assert (deep= @[9 9] (compute/to-array child)) "retained child survives parent")
(assert-error "closed parent rejects access" (compute/to-array parent))
(compute/close parent)

(def matrix (compute/matrix engine :f32 [2 3] [1 2 3 4 5 6]))
(def row (compute/row matrix 1))
(assert (= (compute/storage-id matrix) (compute/storage-id row))
        "row shares storage")
(assert (deep= @[4 5 6] (compute/to-array row)) "row values")

(def transposed (compute/transpose matrix))
(assert (= (compute/storage-id matrix) (compute/storage-id transposed))
        "transpose shares storage")
(assert (deep= @[3 2] (compute/shape transposed)) "transpose shape")
(assert (deep= @[1 3] (compute/strides transposed)) "transpose strides")
(assert (deep= @[1 4 2 5 3 6] (compute/to-array transposed))
        "transpose logical values")

(assert-error "slice bounds" (compute/slice child 1 2))
(assert-error "row rank" (compute/row child 0))
(assert-error "transpose rank" (compute/transpose child))

(end-suite)

(start-suite "Compute operations")

(def x (compute/vector engine :f64 [1 2 3]))
(def y (compute/vector engine :f64 [4 5 6]))
(assert (= 32 (compute/dot x y)) "dot")
(compute/scal! x 2)
(assert (deep= @[2 4 6] (compute/to-array x)) "scal")
(compute/axpy! y 0.5 x)
(assert (deep= @[5 7 9] (compute/to-array y)) "axpy")

(def overlap (compute/vector engine :f32 [1 2 3 4]))
(compute/copy! (compute/slice overlap 1 3)
               (compute/slice overlap 0 3))
(assert (deep= @[1 1 2 3] (compute/to-array overlap))
        "overlapping copy is stable")

(def overlap-axpy (compute/vector engine :f32 [1 2 3 4]))
(compute/axpy! (compute/slice overlap-axpy 1 3) 1
               (compute/slice overlap-axpy 0 3))
(assert (deep= @[1 3 5 7] (compute/to-array overlap-axpy))
        "overlapping axpy reads a stable source")

(def integers (compute/vector engine :i32 [1 1073741824]))
(assert-error "integer overflow" (compute/scal! integers 2))
(assert (deep= @[1 1073741824] (compute/to-array integers))
        "failed integer operation is atomic")

(def a (compute/matrix engine :f32 [2 3] [1 2 3 4 5 6]))
(def b (compute/matrix engine :f32 [3 2] [7 8 9 10 11 12]))
(def product (compute/mm a b))
(assert (deep= @[2 2] (compute/shape product)) "product shape")
(assert (deep= @[58 64 139 154] (compute/to-array product)) "matrix product")

(def at-a (compute/mm (compute/transpose a) a))
(assert (deep= @[3 3] (compute/shape at-a)) "strided product shape")
(assert (deep= @[17 22 27 22 29 36 27 36 45] (compute/to-array at-a))
        "strided matrix product")

(assert-error "copy shape mismatch"
              (compute/copy! (compute/vector engine :f32 [1])
                             (compute/vector engine :f32 [1 2])))
(assert-error "copy dtype mismatch"
              (compute/copy! (compute/vector engine :f32 [1])
                             (compute/vector engine :f64 [1])))
(assert-error "dot requires vectors" (compute/dot a a))
(assert-error "matrix dimensions" (compute/mm a a))

(end-suite)

(start-suite "Compute lifetime stress")

(loop [i :range [0 1000]]
  (def owner (compute/vector engine :f32 [i (+ i 1)]))
  (def retained (compute/slice owner 1 1))
  (compute/close owner)
  (assert (= (+ i 1) (compute/get retained 0)) "retained storage"))
(gccollect)
(assert true "native views survived collection stress")

(end-suite)
