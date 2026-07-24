(import ./compute/native :as native)

(def- dtype-codes {:f32 1 :f64 2 :i32 3})
(def- dtypes {1 :f32 2 :f64 3 :i32})

(defn- dtype-code [dtype]
  (or (dtype-codes dtype)
      (error (string "unsupported dtype " (describe dtype)
                     "; expected :f32, :f64, or :i32"))))

(defn alloc
  "Allocate a zero-filled native view with `dtype` and `shape` on `engine`."
  [engine dtype shape]
  (native/new-view engine (dtype-code dtype) (array ;shape) @[] false))

(defn from-array
  "Allocate a native view and copy the row-major `values` into it."
  [engine dtype shape values]
  (native/new-view engine (dtype-code dtype) (array ;shape) (array ;values) true))

(defn vector
  "Allocate a rank-one native view from `values`."
  [engine dtype values]
  (def data (array ;values))
  (native/new-view engine (dtype-code dtype) @[(length data)] data true))

(defn matrix
  "Allocate a rank-two native view from row-major `values`."
  [engine dtype shape values]
  (def dimensions (array ;shape))
  (unless (= 2 (length dimensions)) (error "matrix shape must have two dimensions"))
  (native/new-view engine (dtype-code dtype) dimensions (array ;values) true))

(defn engine
  "Return the engine that owns `view`."
  [view]
  (native/view-engine view))

(defn engine-name
  "Return the stable name of an engine."
  [engine]
  (native/engine-name engine))

(defn engine-device-name
  "Return the name of the host or device used by an engine."
  [engine]
  (native/engine-device-name engine))

(defn engine-id
  "Return the stable numeric identity of the native engine behind a handle.

  Every handle to one native engine reports one identity, so identities
  compare engines exactly where handles cannot. Like storage-id, this is
  identity inspection admitted for clients that key caches and validate
  engine agreement."
  [engine]
  (native/engine-id engine))

(def- capability-cache @{})

(defn- describe-capabilities
  [engine]
  (def backend (keyword (engine-name engine)))
  (unless (or (= :cpp backend) (= :opencl backend))
    (errorf "unknown compute backend %v" backend))
  (def fp64? (native/engine-fp64? engine))
  (def all-dtypes
    (if fp64?
      [:f32 :f64 :i32]
      [:f32 :i32]))
  (def numerical-dtypes
    (if (= :cpp backend)
      all-dtypes
      (if fp64?
        [:f32 :f64]
        [:f32])))
  (freeze
    {:contract :compute-0
     :backend backend
     :device (engine-device-name engine)
     :dtypes all-dtypes
     :views [:slice :row :transpose]
     :synchronous
     {:alloc all-dtypes
      :transfer all-dtypes
      :get all-dtypes
      :put all-dtypes
      :fill all-dtypes
      :copy all-dtypes
      :scal numerical-dtypes
      :axpy numerical-dtypes
      :dot numerical-dtypes
      :mm numerical-dtypes}
     :queued
     {:fill all-dtypes
      :copy all-dtypes
      :scal numerical-dtypes
      :axpy numerical-dtypes
      :dot numerical-dtypes
      :mm numerical-dtypes}
     :execution
     {:immediate-events (= :cpp backend)
      :asynchronous (= :opencl backend)
      :opencl-c (= :opencl backend)}}))

(defn capabilities
  "Return the immutable compute-0 capability description for `engine`.

  The description is computed once per native engine, keyed by engine-id,
  and cached."
  [engine]
  (def id (native/engine-id engine))
  (or (get capability-cache id)
      (let [contract (describe-capabilities engine)]
        (put capability-cache id contract)
        contract)))

(defn supports?
  "Return whether `engine` supports `operation` for `dtype` in `execution`.

  `execution` is `:synchronous` by default or `:queued`."
  [engine operation dtype &opt execution]
  (default execution :synchronous)
  (unless (or (= :synchronous execution) (= :queued execution))
    (error "execution must be :synchronous or :queued"))
  (def supported
    (get-in (capabilities engine) [execution operation]))
  (and supported (not (nil? (find |(= dtype $) supported)))))

(defn dtype
  "Return the dtype keyword of `view`."
  [view]
  (dtypes (native/dtype view)))

(defn rank
  "Return the number of logical axes."
  [view]
  (native/rank view))

(defn shape
  "Return the logical shape as a new array."
  [view]
  (native/shape view))

(defn strides
  "Return the element strides as a new array."
  [view]
  (native/strides view))

(defn count
  "Return the number of logical elements."
  [view]
  (native/count view))

(defn storage-id
  "Return an identity useful for checking whether views share backing storage."
  [view]
  (native/storage-id view))

(defn get
  "Read one value by its row-major logical index."
  [view index]
  (when (< index 0) (error "index must not be negative"))
  (native/get view index))

(defn put!
  "Write one value by its row-major logical index and return `view`."
  [view index value]
  (when (< index 0) (error "index must not be negative"))
  (native/put view index value)
  view)

(defn to-array
  "Copy the logical row-major values into a Janet array."
  [view]
  (native/to-array view))

(defn slice
  "Create a retained zero-copy vector slice."
  [view start length]
  (native/slice view start length))

(defn row
  "Create a retained zero-copy row view of a matrix."
  [view row-index]
  (native/view-row view row-index))

(defn transpose
  "Create a retained zero-copy transposed view of a matrix."
  [view]
  (native/transpose view))

(defn fill!
  "Fill `view` with one value and return it."
  [view value]
  (native/fill view value)
  view)

(defn copy!
  "Copy `source` into equal-shaped `destination` and return the destination."
  [destination source]
  (native/copy destination source)
  destination)

(defn scal!
  "Multiply every value in `view` by `alpha` in place and return the view."
  [view alpha]
  (native/scal view alpha)
  view)

(defn axpy!
  "Compute `y = alpha*x + y` in place and return `y`."
  [y alpha x]
  (native/axpy y alpha x)
  y)

(defn dot
  "Return the dot product of two equal-shaped vectors."
  [x y]
  (native/dot x y))

(defn mm
  "Return the matrix product of `a` and `b`."
  [a b]
  (native/mm a b))

(defn transfer
  "Explicitly copy `source` into new storage owned by `engine`."
  [engine source]
  (native/transfer engine source))

(defn close
  "Release a view eagerly. Retained child views remain valid."
  [view]
  (native/close view))

(defn closed?
  "Return true when a view has been explicitly closed."
  [view]
  (native/closed? view))

(defn close-engine
  "Release an engine handle. Existing views retain the underlying engine."
  [engine]
  (native/close-engine engine))

(defn engine-closed?
  "Return true when an engine handle has been explicitly closed."
  [engine]
  (native/engine-closed? engine))

(defn sync
  "Wait for work submitted through an engine's internal queue."
  [engine]
  (native/sync engine))

(defn queue
  "Create an explicit command queue for an engine."
  [engine]
  (native/new-queue engine))

(defn finish
  "Wait for every command submitted to `queue`."
  [queue]
  (native/finish queue))

(defn enqueue-fill!
  "Submit a fill after any dependency events and return its event."
  [queue view value & dependencies]
  (native/enqueue-fill queue view value (array ;dependencies)))

(defn enqueue-copy!
  "Submit an overlap-safe copy after dependency events and return its event."
  [queue destination source & dependencies]
  (native/enqueue-copy queue destination source (array ;dependencies)))

(defn enqueue-scal!
  "Submit an in-place scale after dependency events and return its event."
  [queue view alpha & dependencies]
  (native/enqueue-scal queue view alpha (array ;dependencies)))

(defn enqueue-axpy!
  "Submit `y = alpha*x + y` after dependency events and return its event."
  [queue y alpha x & dependencies]
  (native/enqueue-axpy queue y alpha x (array ;dependencies)))

(defn enqueue-dot
  "Submit a dot product and return `[one-element-result event]`."
  [queue x y & dependencies]
  (native/enqueue-dot queue x y (array ;dependencies)))

(defn enqueue-mm
  "Submit matrix multiplication and return `[result event]`."
  [queue a b & dependencies]
  (native/enqueue-mm queue a b (array ;dependencies)))

(defn wait
  "Wait for `event` and return it."
  [event]
  (native/wait event)
  event)

(defn event-complete?
  "Return true when an event has completed."
  [event]
  (native/event-complete? event))

(defn close-queue
  "Release a command queue eagerly."
  [queue]
  (native/close-queue queue))

(defn queue-closed?
  "Return true when a command queue has been explicitly closed."
  [queue]
  (native/queue-closed? queue))

(defn close-event
  "Release an event eagerly."
  [event]
  (native/close-event event))

(defn event-closed?
  "Return true when an event has been explicitly closed."
  [event]
  (native/event-closed? event))
