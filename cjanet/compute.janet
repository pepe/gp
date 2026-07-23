(use spork/cjanet)

(include <janet.h>)
(include <compute-helper.h>)

(typedef Engine (named-struct Engine native (* GpComputeEngine)))
(typedef View (named-struct View native (* GpComputeView)))

(function gc-view :static [p:*void size:size_t] -> int
  (def view:*View p)
  (when view->native (gp-compute-view-free view->native))
  (return 0))

(abstract-type Engine :name "gp/compute-engine")
(abstract-type View :name "gp/compute-view" :gc gc-view)

(function require-view :static [view:*View] -> *GpComputeView
  (unless view->native (janet-panic "compute view is closed"))
  (return view->native))

(function new-view-box :static [] -> *View
  (def view:*View (janet-abstract View-ATP (sizeof View)))
  (set view->native NULL)
  (return view))

(function wrap-engine :static [native:*GpComputeEngine] -> *Engine
  (def engine:*Engine (janet-abstract Engine-ATP (sizeof Engine)))
  (set engine->native native)
  (return engine))

(cfunction cpp-engine "Return the synchronous C++ reference engine." [] -> *Engine
  (return (wrap-engine (gp-compute-cpp-engine))))

(cfunction engine-name "Return the engine name." [engine:*Engine] -> string
  (return (janet-cstring (gp-compute-engine-name engine->native))))

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
    (gp-compute-view-new engine->native dtype dimensions rank
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
  (return (wrap-engine (gp-compute-view-engine (require-view view)))))

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

(module-entry "compute/cpp-native")
