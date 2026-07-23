(use spork/cjanet)

(include <janet.h>)
(include <compute-helper.h>)

(typedef Engine (named-struct Engine native (* GpComputeEngine)))
(typedef View (named-struct View native (* GpComputeView)))
(typedef Queue (named-struct Queue native (* GpComputeQueue)))
(typedef Event (named-struct Event native (* GpComputeEvent)))

(function gc-view :static [p:*void size:size_t] -> int
  (def view:*View p)
  (when view->native (gp-compute-view-free view->native))
  (return 0))

(function gc-engine :static [p:*void size:size_t] -> int
  (def engine:*Engine p)
  (when engine->native (gp-compute-engine-free engine->native))
  (return 0))

(function gc-queue :static [p:*void size:size_t] -> int
  (def queue:*Queue p)
  (when queue->native (gp-compute-queue-free queue->native))
  (return 0))

(function gc-event :static [p:*void size:size_t] -> int
  (def event:*Event p)
  (when event->native (gp-compute-event-free event->native))
  (return 0))

(abstract-type Engine :name "gp/compute-engine" :gc gc-engine)
(abstract-type View :name "gp/compute-view" :gc gc-view)
(abstract-type Queue :name "gp/compute-queue" :gc gc-queue)
(abstract-type Event :name "gp/compute-event" :gc gc-event)

(function require-engine :static [engine:*Engine] -> *GpComputeEngine
  (unless engine->native (janet-panic "compute engine is closed"))
  (return engine->native))

(function require-view :static [view:*View] -> *GpComputeView
  (unless view->native (janet-panic "compute view is closed"))
  (return view->native))

(function require-queue :static [queue:*Queue] -> *GpComputeQueue
  (unless queue->native (janet-panic "compute queue is closed"))
  (return queue->native))

(function require-event :static [event:*Event] -> *GpComputeEvent
  (unless event->native (janet-panic "compute event is closed"))
  (return event->native))

(function new-view-box :static [] -> *View
  (def view:*View (janet-abstract View-ATP (sizeof View)))
  (set view->native NULL)
  (return view))

(function new-engine-box :static [] -> *Engine
  (def engine:*Engine (janet-abstract Engine-ATP (sizeof Engine)))
  (set engine->native NULL)
  (return engine))

(function new-queue-box :static [] -> *Queue
  (def queue:*Queue (janet-abstract Queue-ATP (sizeof Queue)))
  (set queue->native NULL)
  (return queue))

(function new-event-box :static [] -> *Event
  (def event:*Event (janet-abstract Event-ATP (sizeof Event)))
  (set event->native NULL)
  (return event))

(cfunction cpp-engine "Return the synchronous C++ reference engine." [] -> *Engine
  (def engine:*Engine (new-engine-box))
  (set engine->native (gp-compute-cpp-engine))
  (return engine))

(cfunction engine-name "Return the engine name." [engine:*Engine] -> string
  (return (janet-cstring (gp-compute-engine-name (require-engine engine)))))

(cfunction engine-device-name "Return the engine device name." [engine:*Engine] -> string
  (return (janet-cstring (gp-compute-engine-device-name (require-engine engine)))))

(cfunction close-engine "Release an engine handle. Its existing views remain valid." [engine:*Engine] -> bool
  (when engine->native
    (gp-compute-engine-free engine->native)
    (set engine->native NULL))
  (return true))

(cfunction engine-closed? "Return true when an engine handle is explicitly closed." [engine:*Engine] -> bool
  (return (== engine->native NULL)))

(cfunction sync "Wait for work on an engine's internal queue." [engine:*Engine] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-engine-sync (require-engine engine)
                                   (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction new-queue "Create a command queue for an engine." [engine:*Engine] -> *Queue
  (def queue:*Queue (new-queue-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeQueue
    (gp-compute-queue-new (require-engine engine)
                          (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set queue->native native)
  (return queue))

(cfunction close-queue "Release a command queue." [queue:*Queue] -> bool
  (when queue->native
    (gp-compute-queue-free queue->native)
    (set queue->native NULL))
  (return true))

(cfunction queue-closed? "Return true when a command queue is closed." [queue:*Queue] -> bool
  (return (== queue->native NULL)))

(cfunction finish "Wait for every command submitted to a queue." [queue:*Queue] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-queue-finish (require-queue queue)
                                    (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction enqueue-fill
  "Submit a fill and return an event."
  [queue:*Queue view:*View value:number dependencies:array] -> *Event
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-view:*GpComputeView (require-view view))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "fill dependencies must be compute events"))
    (def dependency:*Event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (require-event dependency)
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (def dependency:*Event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (set (aref native-dependencies index) (require-event dependency))
    (++ index))
  (def (message (array char 512)) nil)
  (def native:*GpComputeEvent
    (gp-compute-enqueue-fill
      native-queue native-view value
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native (janet-panic (addr (aref message 0))))
  (set event->native native)
  (return event))

(cfunction enqueue-copy
  "Submit an overlap-safe copy and return an event."
  [queue:*Queue destination:*View source:*View dependencies:array] -> *Event
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-destination:*GpComputeView (require-view destination))
  (def native-source:*GpComputeView (require-view source))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "copy dependencies must be compute events"))
    (def dependency:*Event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (require-event dependency)
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (def dependency:*Event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (set (aref native-dependencies index) (require-event dependency))
    (++ index))
  (def (message (array char 512)) nil)
  (def native:*GpComputeEvent
    (gp-compute-enqueue-copy
      native-queue native-destination native-source
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native (janet-panic (addr (aref message 0))))
  (set event->native native)
  (return event))

(cfunction enqueue-scal
  "Submit an in-place scale and return an event."
  [queue:*Queue view:*View alpha:number dependencies:array] -> *Event
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-view:*GpComputeView (require-view view))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "scal dependencies must be compute events"))
    (require-event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (set (aref native-dependencies index)
         (require-event
           (janet-unwrap-abstract (aref dependencies->data index))))
    (++ index))
  (def (message (array char 512)) nil)
  (def native:*GpComputeEvent
    (gp-compute-enqueue-scal
      native-queue native-view alpha
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native (janet-panic (addr (aref message 0))))
  (set event->native native)
  (return event))

(cfunction enqueue-axpy
  "Submit y = alpha*x + y in place and return an event."
  [queue:*Queue y:*View alpha:number x:*View dependencies:array] -> *Event
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-y:*GpComputeView (require-view y))
  (def native-x:*GpComputeView (require-view x))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "axpy dependencies must be compute events"))
    (require-event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (set (aref native-dependencies index)
         (require-event
           (janet-unwrap-abstract (aref dependencies->data index))))
    (++ index))
  (def (message (array char 512)) nil)
  (def native:*GpComputeEvent
    (gp-compute-enqueue-axpy
      native-queue native-y alpha native-x
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native (janet-panic (addr (aref message 0))))
  (set event->native native)
  (return event))

(cfunction enqueue-dot
  "Submit a dot product and return [one-element-result event]."
  [queue:*Queue x:*View y:*View dependencies:array] -> JanetTuple
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-x:*GpComputeView (require-view x))
  (def native-y:*GpComputeView (require-view y))
  (def result-view:*View (new-view-box))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "dot dependencies must be compute events"))
    (require-event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (set (aref native-dependencies index)
         (require-event
           (janet-unwrap-abstract (aref dependencies->data index))))
    (++ index))
  (def native-result:*GpComputeView NULL)
  (def (message (array char 512)) nil)
  (def native-event:*GpComputeEvent
    (gp-compute-enqueue-dot
      native-queue native-x native-y (addr native-result)
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native-event (janet-panic (addr (aref message 0))))
  (set result-view->native native-result)
  (set event->native native-event)
  (def result:*Janet (janet-tuple-begin 2))
  (set (aref result 0) (janet-wrap-abstract result-view))
  (set (aref result 1) (janet-wrap-abstract event))
  (return (janet-tuple-end result)))

(cfunction enqueue-mm
  "Submit matrix multiplication and return [result event]."
  [queue:*Queue a:*View b:*View dependencies:array] -> JanetTuple
  (def native-queue:*GpComputeQueue (require-queue queue))
  (def native-a:*GpComputeView (require-view a))
  (def native-b:*GpComputeView (require-view b))
  (def result-view:*View (new-view-box))
  (def event:*Event (new-event-box))
  (def dependency-count:int32_t dependencies->count)
  (def index:int32_t 0)
  (while (< index dependency-count)
    (unless (janet-checkabstract (aref dependencies->data index) Event-ATP)
      (janet-panic "mm dependencies must be compute events"))
    (require-event
      (janet-unwrap-abstract (aref dependencies->data index)))
    (++ index))
  (def **native-dependencies:GpComputeEvent
    (janet-malloc (* (+ dependency-count 1) (sizeof uintptr_t))))
  (unless native-dependencies JANET_OUT_OF_MEMORY)
  (set index 0)
  (while (< index dependency-count)
    (set (aref native-dependencies index)
         (require-event
           (janet-unwrap-abstract (aref dependencies->data index))))
    (++ index))
  (def native-result:*GpComputeView NULL)
  (def (message (array char 512)) nil)
  (def native-event:*GpComputeEvent
    (gp-compute-enqueue-mm
      native-queue native-a native-b (addr native-result)
      native-dependencies dependency-count
      (addr (aref message 0)) 512))
  (janet-free native-dependencies)
  (unless native-event (janet-panic (addr (aref message 0))))
  (set result-view->native native-result)
  (set event->native native-event)
  (def result:*Janet (janet-tuple-begin 2))
  (set (aref result 0) (janet-wrap-abstract result-view))
  (set (aref result 1) (janet-wrap-abstract event))
  (return (janet-tuple-end result)))

(cfunction wait "Wait for an event." [event:*Event] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-event-wait (require-event event)
                                  (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction event-complete? "Return true when an event has completed." [event:*Event] -> bool
  (def (message (array char 512)) nil)
  (def complete:int
    (gp-compute-event-complete (require-event event)
                               (addr (aref message 0)) 512))
  (when (< complete 0) (janet-panic (addr (aref message 0))))
  (return (!= complete 0)))

(cfunction close-event "Release an event." [event:*Event] -> bool
  (when event->native
    (gp-compute-event-free event->native)
    (set event->native NULL))
  (return true))

(cfunction event-closed? "Return true when an event is closed." [event:*Event] -> bool
  (return (== event->native NULL)))

(cfunction opencl-available? "Return true when at least one OpenCL platform is available." [] -> bool
  (def (message (array char 512)) nil)
  (return (> (gp-compute-opencl-platform-count
               (addr (aref message 0)) 512) 0)))

(cfunction opencl-platform-count "Return the number of OpenCL platforms." [] -> int
  (def (message (array char 512)) nil)
  (def count:int (gp-compute-opencl-platform-count
                   (addr (aref message 0)) 512))
  (when (< count 0) (janet-panic (addr (aref message 0))))
  (return count))

(cfunction opencl-platform-name "Return an OpenCL platform name." [platform:int] -> string
  (def (value (array char 512)) nil)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-opencl-platform-name
             platform (addr (aref value 0)) 512
             (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return (janet-cstring (addr (aref value 0)))))

(cfunction opencl-device-count "Return an OpenCL platform's device count." [platform:int] -> int
  (def (message (array char 512)) nil)
  (def count:int (gp-compute-opencl-device-count
                   platform (addr (aref message 0)) 512))
  (when (< count 0) (janet-panic (addr (aref message 0))))
  (return count))

(cfunction opencl-device-name "Return an OpenCL device name." [platform:int device:int] -> string
  (def (value (array char 512)) nil)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-opencl-device-name
             platform device (addr (aref value 0)) 512
             (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return (janet-cstring (addr (aref value 0)))))

(cfunction opencl-device-vendor "Return an OpenCL device vendor." [platform:int device:int] -> string
  (def (value (array char 512)) nil)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-opencl-device-vendor
             platform device (addr (aref value 0)) 512
             (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return (janet-cstring (addr (aref value 0)))))

(cfunction opencl-device-version "Return an OpenCL device version." [platform:int device:int] -> string
  (def (value (array char 512)) nil)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-opencl-device-version
             platform device (addr (aref value 0)) 512
             (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return (janet-cstring (addr (aref value 0)))))

(cfunction opencl-device-fp64? "Return true when an OpenCL device supports f64." [platform:int device:int] -> bool
  (def (message (array char 512)) nil)
  (def supported:int
    (gp-compute-opencl-device-fp64
      platform device (addr (aref message 0)) 512))
  (when (< supported 0) (janet-panic (addr (aref message 0))))
  (return (!= supported 0)))

(cfunction opencl-device-global-memory "Return OpenCL global memory in bytes." [platform:int device:int] -> number
  (def (message (array char 512)) nil)
  (def bytes:double
    (gp-compute-opencl-device-global-memory
      platform device (addr (aref message 0)) 512))
  (when (< bytes 0) (janet-panic (addr (aref message 0))))
  (return bytes))

(cfunction new-opencl-engine "Create an OpenCL engine for a platform and device." [platform:int device:int] -> *Engine
  (def engine:*Engine (new-engine-box))
  (def (message (array char 2048)) nil)
  (def native:*GpComputeEngine
    (gp-compute-opencl-engine-new
      platform device (addr (aref message 0)) 2048))
  (unless native (janet-panic (addr (aref message 0))))
  (set engine->native native)
  (return engine))

(cfunction new-view
  "Allocate an owned, zero-initialized native view and optionally copy values into it."
  [engine:*Engine dtype:int shape:array values:array has-values:bool] -> *View
  (def rank:int32_t shape->count)
  (def axis:int32_t 0)
  (while (< axis rank)
    (unless (janet-checkint64 (aref shape->data axis))
      (janet-panic "shape dimensions must be integers"))
    (++ axis))
  (def value-index:int32_t 0)
  (while (and has-values (< value-index values->count))
    (unless (janet-checktype (aref values->data value-index) JANET_NUMBER)
      (janet-panic "compute values must be numbers"))
    (++ value-index))
  (def native-engine:*GpComputeEngine (require-engine engine))
  (def view:*View (new-view-box))
  (def *dimensions:int64_t
    (janet-malloc (* (+ rank 1) (sizeof int64_t))))
  (unless dimensions JANET_OUT_OF_MEMORY)
  (set axis 0)
  (while (< axis rank)
    (set (aref dimensions axis) (janet-getinteger64 shape->data axis))
    (++ axis))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-view-new native-engine dtype dimensions rank
                         (addr (aref message 0)) 512))
  (janet-free dimensions)
  (unless native (janet-panic (addr (aref message 0))))
  (def count:uint64_t (gp-compute-view-count native))
  (when (and has-values (!= (cast uint64_t values->count) count))
    (gp-compute-view-free native)
    (janet-panic "value count does not match shape"))
  (def index:uint64_t 0)
  (while (and has-values (< index (cast uint64_t values->count)))
    (def value:double (janet-getnumber values->data (cast int32_t index)))
    (when (< (gp-compute-view-set native index value
                                  (addr (aref message 0)) 512) 0)
      (gp-compute-view-free native)
      (janet-panic (addr (aref message 0))))
    (++ index))
  (set view->native native)
  (return view))

(cfunction close "Release this view. Retained child views remain valid." [view:*View] -> bool
  (when view->native
    (gp-compute-view-free view->native)
    (set view->native NULL))
  (return true))

(cfunction closed? "Return true when a view has been explicitly closed." [view:*View] -> bool
  (return (== view->native NULL)))

(cfunction dtype "Return the native dtype code." [view:*View] -> int
  (return (gp-compute-view-dtype (require-view view))))

(cfunction rank "Return the view rank." [view:*View] -> int
  (return (gp-compute-view-rank (require-view view))))

(cfunction shape "Return the logical shape." [view:*View] -> array
  (def native:*GpComputeView (require-view view))
  (def rank:int32_t (gp-compute-view-rank native))
  (def result:*JanetArray (janet-array rank))
  (def axis:int32_t 0)
  (while (< axis rank)
    (janet-array-push result
      (janet-wrap-number (cast double (gp-compute-view-shape native axis))))
    (++ axis))
  (return result))

(cfunction strides "Return element strides for each logical axis." [view:*View] -> array
  (def native:*GpComputeView (require-view view))
  (def rank:int32_t (gp-compute-view-rank native))
  (def result:*JanetArray (janet-array rank))
  (def axis:int32_t 0)
  (while (< axis rank)
    (janet-array-push result
      (janet-wrap-number (cast double (gp-compute-view-stride native axis))))
    (++ axis))
  (return result))

(cfunction count "Return the number of logical elements." [view:*View] -> number
  (return (cast double (gp-compute-view-count (require-view view)))))

(cfunction storage-id "Return an identity for the retained backing storage." [view:*View] -> number
  (return (cast double (gp-compute-view-storage-id (require-view view)))))

(cfunction view-engine "Return the engine that owns this view." [view:*View] -> *Engine
  (def engine:*Engine (new-engine-box))
  (def native:*GpComputeEngine (gp-compute-view-engine (require-view view)))
  (gp-compute-engine-retain native)
  (set engine->native native)
  (return engine))

(cfunction get "Read a value by row-major logical index." [view:*View index:uint64_t] -> number
  (def value:double 0)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-view-get (require-view view) index (addr value)
                                (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return value))

(cfunction put "Write a value by row-major logical index." [view:*View index:uint64_t value:number] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-view-set (require-view view) index value
                                (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction to-array "Copy logical values into a Janet array." [view:*View] -> array
  (def native:*GpComputeView (require-view view))
  (def count:uint64_t (gp-compute-view-count native))
  (when (> count INT32_MAX) (janet-panic "view is too large for a Janet array"))
  (def result:*JanetArray (janet-array (cast int32_t count)))
  (def (message (array char 512)) nil)
  (def index:uint64_t 0)
  (while (< index count)
    (def value:double 0)
    (when (< (gp-compute-view-get native index (addr value)
                                  (addr (aref message 0)) 512) 0)
      (janet-panic (addr (aref message 0))))
    (janet-array-push result (janet-wrap-number value))
    (++ index))
  (return result))

(cfunction slice "Create a retained zero-copy vector slice." [view:*View start:int64_t length:int64_t] -> *View
  (def result:*View (new-view-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-view-slice (require-view view) start length
                           (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set result->native native)
  (return result))

(cfunction view-row "Create a retained zero-copy matrix row view." [view:*View row-index:int64_t] -> *View
  (def result:*View (new-view-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-view-row (require-view view) row-index
                         (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set result->native native)
  (return result))

(cfunction transpose "Create a retained zero-copy transposed matrix view." [view:*View] -> *View
  (def result:*View (new-view-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-view-transpose (require-view view)
                               (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set result->native native)
  (return result))

(cfunction fill "Fill a view with one value." [view:*View value:number] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-fill (require-view view) value
                            (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction copy "Copy between equal-shaped views, including overlapping views." [destination:*View source:*View] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-copy (require-view destination) (require-view source)
                            (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction scal "Scale all values in place." [view:*View alpha:number] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-scal (require-view view) alpha
                            (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction axpy "Compute y = alpha*x + y in place." [y:*View alpha:number x:*View] -> bool
  (def (message (array char 512)) nil)
  (when (< (gp-compute-axpy (require-view y) alpha (require-view x)
                            (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return true))

(cfunction dot "Return the vector dot product." [x:*View y:*View] -> number
  (def result:double 0)
  (def (message (array char 512)) nil)
  (when (< (gp-compute-dot (require-view x) (require-view y) (addr result)
                           (addr (aref message 0)) 512) 0)
    (janet-panic (addr (aref message 0))))
  (return result))

(cfunction mm "Return matrix multiplication a*b." [a:*View b:*View] -> *View
  (def result:*View (new-view-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-mm (require-view a) (require-view b)
                   (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set result->native native)
  (return result))

(cfunction transfer "Explicitly copy a view to another engine." [engine:*Engine source:*View] -> *View
  (def result:*View (new-view-box))
  (def (message (array char 512)) nil)
  (def native:*GpComputeView
    (gp-compute-transfer (require-engine engine) (require-view source)
                         (addr (aref message 0)) 512))
  (unless native (janet-panic (addr (aref message 0))))
  (set result->native native)
  (return result))

(module-entry "compute/native")
