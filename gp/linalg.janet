(import gp/compute)
(import gp/kernel)

# linalg-0 value layer: structured vectors and matrices over compute-0
# views. Storage is always dense; structure lives in metadata. See
# docs/linalg.md for the value model and conventions.

(def- uplo-kinds {:lower true :upper true})
(def- diag-kinds {:unit true :non-unit true})

(defn linalg?
  "Return true when `value` is a gp/linalg vector or matrix."
  [value]
  (and (dictionary? value) (= true (get value :gp/linalg))))

(defn- require-linalg
  [value]
  (unless (linalg? value) (error "expected a gp/linalg value"))
  value)

(defn structure
  "Return the structure keyword: :vctr, :ge, :tr, :sy, or :gd."
  [value]
  ((require-linalg value) :structure))

(defn vector?
  "Return true when `value` is a gp/linalg vector."
  [value]
  (and (linalg? value) (= :vctr (value :structure))))

(defn matrix?
  "Return true when `value` is a gp/linalg matrix."
  [value]
  (and (linalg? value) (not= :vctr (value :structure))))

(defn- require-vector
  [x]
  (unless (vector? x) (error "expected a gp/linalg vector"))
  x)

(defn- require-matrix
  [a]
  (unless (matrix? a) (error "expected a gp/linalg matrix"))
  a)

(defn view
  "Return the compute view that stores `value`."
  [value]
  ((require-linalg value) :view))

(defn engine
  "Return the compute engine that owns `value`."
  [value]
  (compute/engine (view value)))

(defn dtype
  "Return the dtype keyword of `value`."
  [value]
  (compute/dtype (view value)))

(defn dim
  "Return the number of entries in a vector."
  [x]
  (compute/count (view (require-vector x))))

(defn mrows
  "Return the number of matrix rows."
  [a]
  (first (compute/shape (view (require-matrix a)))))

(defn ncols
  "Return the number of matrix columns."
  [a]
  (get (compute/shape (view (require-matrix a))) 1))

(defn uplo
  "Return which triangle of a :tr or :sy matrix is stored, :lower or :upper."
  [a]
  (require-linalg a)
  (unless (get {:tr true :sy true} (a :structure))
    (error "uplo is defined for :tr and :sy matrices"))
  (a :uplo))

(defn unit-diag?
  "Return true when a :tr matrix has an implicit unit diagonal."
  [a]
  (require-linalg a)
  (unless (= :tr (a :structure))
    (error "unit-diag? is defined for :tr matrices"))
  (= :unit (a :diag)))

(defn vctr
  "Allocate a dense vector on `engine` from `values`."
  [engine dtype values]
  {:gp/linalg true :structure :vctr
   :view (compute/vector engine dtype values)})

(defn ge
  "Allocate a dense `rows`-by-`cols` general matrix from row-major `values`."
  [engine dtype rows cols values]
  {:gp/linalg true :structure :ge
   :view (compute/matrix engine dtype [rows cols] values)})

(defn- require-uplo
  [uplo]
  (unless (get uplo-kinds uplo)
    (errorf "uplo must be :lower or :upper, got %v" uplo))
  uplo)

(defn tr
  "Allocate an `n`-by-`n` triangular matrix from row-major dense `values`.

  `uplo` selects the stored triangle (default :lower) and `diag` may be
  :unit for an implicit unit diagonal (default :non-unit). Entries outside
  the stored triangle are logically zero regardless of `values`."
  [engine dtype n values &opt uplo diag]
  (default uplo :lower)
  (default diag :non-unit)
  (require-uplo uplo)
  (unless (get diag-kinds diag)
    (errorf "diag must be :unit or :non-unit, got %v" diag))
  {:gp/linalg true :structure :tr :uplo uplo :diag diag
   :view (compute/matrix engine dtype [n n] values)})

(defn sy
  "Allocate an `n`-by-`n` symmetric matrix from row-major dense `values`.

  Only the `uplo` triangle (default :lower) is significant; the other
  triangle is logically mirrored from it."
  [engine dtype n values &opt uplo]
  (default uplo :lower)
  (require-uplo uplo)
  {:gp/linalg true :structure :sy :uplo uplo
   :view (compute/matrix engine dtype [n n] values)})

(defn gd
  "Allocate an `n`-by-`n` diagonal matrix from the `n` `diagonal` values."
  [engine dtype n diagonal]
  (unless (= n (length diagonal))
    (errorf "diagonal must have %v values, got %v" n (length diagonal)))
  (def storage (compute/alloc engine dtype [n n]))
  (loop [i :range [0 n]]
    (compute/put! storage (+ (* i n) i) (get diagonal i)))
  {:gp/linalg true :structure :gd :view storage})

(defn- check-index
  [index limit what]
  (unless (and (number? index)
               (= index (math/floor index))
               (>= index 0)
               (< index limit))
    (errorf "%s index %v is out of bounds for %v" what index limit)))

(defn- stored?
  [value i j]
  (case (value :structure)
    :ge true
    :tr (if (= :lower (value :uplo)) (>= i j) (<= i j))
    :sy (if (= :lower (value :uplo)) (>= i j) (<= i j))
    :gd (= i j)))

(defn entry
  "Return one logical entry: `(entry x i)` for vectors, `(entry a i j)`
  for matrices.

  Reads are logical, not raw storage reads: a :tr matrix reads zero outside
  its stored triangle and one on a :unit diagonal, a :sy matrix mirrors its
  stored triangle, and a :gd matrix reads zero off the diagonal."
  [value i &opt j]
  (require-linalg value)
  (if (= :vctr (value :structure))
    (do
      (unless (nil? j) (error "vector entries take one index"))
      (check-index i (compute/count (value :view)) "vector")
      (compute/get (value :view) i))
    (do
      (when (nil? j) (error "matrix entries take a row and a column index"))
      (def [m n] (compute/shape (value :view)))
      (check-index i m "row")
      (check-index j n "column")
      (cond
        (and (= :tr (value :structure)) (= i j) (= :unit (value :diag)))
        1
        (stored? value i j)
        (compute/get (value :view) (+ (* i n) j))
        (= :sy (value :structure))
        (compute/get (value :view) (+ (* j n) i))
        0))))

(defn entry!
  "Write one stored entry and return `value`: `(entry! x i e)` for vectors,
  `(entry! a i j e)` for matrices.

  Writes must target stored entries: anywhere for :vctr and :ge, within the
  stored triangle for :tr and :sy, never on a :unit diagonal, and only on
  the diagonal for :gd."
  [value i j &opt e]
  (require-linalg value)
  (if (= :vctr (value :structure))
    (do
      (unless (nil? e) (error "vector entries take one index"))
      (check-index i (compute/count (value :view)) "vector")
      (compute/put! (value :view) i j)
      value)
    (do
      (when (nil? e) (error "matrix writes take a row index, a column index, and a value"))
      (def [m n] (compute/shape (value :view)))
      (check-index i m "row")
      (check-index j n "column")
      (when (and (= :tr (value :structure)) (= i j) (= :unit (value :diag)))
        (error "a :unit diagonal is implicit and cannot be written"))
      (unless (stored? value i j)
        (errorf "structure %v does not store entry [%v %v]"
                (value :structure) i j))
      (compute/put! (value :view) (+ (* i n) j) e)
      value)))

(defn to-array
  "Copy the logical row-major entries into a Janet array.

  Logical means structure-aware: :tr, :sy, and :gd matrices materialize
  their implicit zeros, mirror, and unit diagonal."
  [value]
  (require-linalg value)
  (case (value :structure)
    :vctr (compute/to-array (value :view))
    :ge (compute/to-array (value :view))
    (do
      (def [m n] (compute/shape (value :view)))
      (def out (array/new (* m n)))
      (loop [i :range [0 m]
             j :range [0 n]]
        (array/push out (entry value i j)))
      out)))

(defn trans
  "Return the logical transpose of a matrix.

  :ge and :tr transpose zero-copy over the same storage (a :tr flips its
  stored triangle); :sy and :gd are their own transpose and return `value`
  unchanged."
  [value]
  (require-matrix value)
  (case (value :structure)
    :ge {:gp/linalg true :structure :ge
         :view (compute/transpose (value :view))}
    :tr {:gp/linalg true :structure :tr
         :uplo (if (= :lower (value :uplo)) :upper :lower)
         :diag (value :diag)
         :view (compute/transpose (value :view))}
    value))

(defn row
  "Return a zero-copy vector view of one row of a :ge matrix.

  Rows of structured matrices are not offered because their dense storage
  rows do not represent their logical rows."
  [a i]
  (require-linalg a)
  (unless (= :ge (a :structure))
    (error "row views are defined for :ge matrices"))
  (check-index i (mrows a) "row")
  {:gp/linalg true :structure :vctr
   :view (compute/row (a :view) i)})

(defn col
  "Return a zero-copy vector view of one column of a :ge matrix."
  [a j]
  (require-linalg a)
  (unless (= :ge (a :structure))
    (error "column views are defined for :ge matrices"))
  (check-index j (ncols a) "column")
  {:gp/linalg true :structure :vctr
   :view (compute/row (compute/transpose (a :view)) j)})

(defn subvector
  "Return a zero-copy vector view of `length` entries starting at `start`."
  [x start length]
  (require-vector x)
  {:gp/linalg true :structure :vctr
   :view (compute/slice (x :view) start length)})

(defn transfer
  "Copy `value` into new storage owned by `engine`, preserving structure.

  Like compute-0, transfer is the only way values move between engines;
  nothing transfers implicitly."
  [engine value]
  (require-linalg value)
  (def moved (compute/transfer engine (value :view)))
  (case (value :structure)
    :tr {:gp/linalg true :structure :tr
         :uplo (value :uplo) :diag (value :diag) :view moved}
    :sy {:gp/linalg true :structure :sy
         :uplo (value :uplo) :view moved}
    {:gp/linalg true :structure (value :structure) :view moved}))

(defn- require-same-structure
  [destination source operation]
  (require-linalg destination)
  (require-linalg source)
  (unless (= (destination :structure) (source :structure))
    (errorf "%s requires matching structures, got %v and %v"
            operation (destination :structure) (source :structure)))
  (case (destination :structure)
    :tr (do
          (unless (= (destination :uplo) (source :uplo))
            (errorf "%s requires matching stored triangles" operation))
          (unless (= (destination :diag) (source :diag))
            (errorf "%s requires matching diagonal kinds" operation)))
    :sy (unless (= (destination :uplo) (source :uplo))
          (errorf "%s requires matching stored triangles" operation)))
  destination)

(defn- reject-unit
  [value operation]
  (when (and (= :tr (value :structure)) (= :unit (value :diag)))
    (errorf "%s cannot represent its result on a :unit diagonal" operation)))

(defn scal!
  "Multiply every logical entry of `value` by `alpha` in place and return it.

  A :unit triangular matrix is rejected because its implicit diagonal
  cannot represent the scaled result."
  [value alpha]
  (require-linalg value)
  (reject-unit value "scal!")
  (compute/scal! (value :view) alpha)
  value)

(defn copy!
  "Copy `source` into the structurally identical `destination` and return
  the destination.

  Structures, stored triangles, diagonal kinds, shapes, dtypes, and engines
  must all match; nothing converts or transfers implicitly."
  [destination source]
  (require-same-structure destination source "copy!")
  (compute/copy! (destination :view) (source :view))
  destination)

(defn axpy!
  "Compute `y = alpha*x + y` over logical entries in place and return `y`.

  `y` and `x` must be structurally identical. :unit triangular matrices are
  rejected because their implicit diagonal cannot represent the result."
  [y alpha x]
  (require-same-structure y x "axpy!")
  (reject-unit y "axpy!")
  (compute/axpy! (y :view) alpha (x :view))
  y)

(defn dot
  "Return the dot product of two equal-length vectors."
  [x y]
  (require-vector x)
  (require-vector y)
  (compute/dot (x :view) (y :view)))

(defn- reduce-entries
  [x f initial]
  (def v (view (require-vector x)))
  (var accumulator initial)
  (loop [i :range [0 (compute/count v)]]
    (set accumulator (f accumulator (compute/get v i))))
  accumulator)

# Device kernels for the operations the kernel language can express.
# asum and amax lower through the abs and max admitted at the
# kernel-0.1 review gate — the pressure this module recorded in phase D,
# discharged.

(kernel/defkernel device-asum-f32
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel device-asum-f64
  [n:i32
   (x (buffer :f64 [n] :read))
   (result (buffer :f64 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel device-amax-f32
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce max 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel device-amax-f64
  [n:i32
   (x (buffer :f64 [n] :read))
   (result (buffer :f64 [1] :write))]
  (store! result [0]
    (reduce max 0 [i 0 n] (abs (load x [i])))))

(kernel/defkernel device-sum-f32
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (load x [i]))))

(kernel/defkernel device-sum-f64
  [n:i32
   (x (buffer :f64 [n] :read))
   (result (buffer :f64 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (load x [i]))))

(kernel/defkernel device-square-sum-f32
  [n:i32
   (x (buffer :f32 [n] :read))
   (result (buffer :f32 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (* (load x [i]) (load x [i])))))

(kernel/defkernel device-square-sum-f64
  [n:i32
   (x (buffer :f64 [n] :read))
   (result (buffer :f64 [1] :write))]
  (store! result [0]
    (reduce + 0 [i 0 n] (* (load x [i]) (load x [i])))))

(kernel/defkernel device-mv-f32
  [m:i32 n:i32 alpha:f32 beta:f32
   (a (buffer :f32 [m n] :read))
   (x (buffer :f32 [n] :read))
   (y (buffer :f32 [m] :read-write))]
  (parallel [i 0 m]
    (store! y [i]
      (+ (* alpha (reduce + 0 [j 0 n] (* (load a [i j]) (load x [j]))))
         (* beta (load y [i]))))))

(kernel/defkernel device-mv-f64
  [m:i32 n:i32 alpha:f64 beta:f64
   (a (buffer :f64 [m n] :read))
   (x (buffer :f64 [n] :read))
   (y (buffer :f64 [m] :read-write))]
  (parallel [i 0 m]
    (store! y [i]
      (+ (* alpha (reduce + 0 [j 0 n] (* (load a [i j]) (load x [j]))))
         (* beta (load y [i]))))))

(kernel/defkernel device-mv-gd-f32
  [n:i32 alpha:f32 beta:f32
   (a (buffer :f32 [n n] :read))
   (x (buffer :f32 [n] :read))
   (y (buffer :f32 [n] :read-write))]
  (parallel [i 0 n]
    (store! y [i]
      (+ (* alpha (* (load a [i i]) (load x [i])))
         (* beta (load y [i]))))))

(kernel/defkernel device-mv-gd-f64
  [n:i32 alpha:f64 beta:f64
   (a (buffer :f64 [n n] :read))
   (x (buffer :f64 [n] :read))
   (y (buffer :f64 [n] :read-write))]
  (parallel [i 0 n]
    (store! y [i]
      (+ (* alpha (* (load a [i i]) (load x [i])))
         (* beta (load y [i]))))))

# Kernels are implementation detail, not module API.
(each kernel-symbol
      '[device-sum-f32 device-sum-f64
        device-square-sum-f32 device-square-sum-f64
        device-asum-f32 device-asum-f64
        device-amax-f32 device-amax-f64
        device-mv-f32 device-mv-f64
        device-mv-gd-f32 device-mv-gd-f64]
  (put (get (curenv) kernel-symbol) :private true))

(def- device-kernel-cache @{})

(defn- launch-device-kernel
  # Compiled programs cache exactly per native engine identity and
  # kernel; a fresh engine on the same device compiles its own program.
  [owner kernel queue bindings]
  (def key [(compute/engine-id owner) (kernel/name kernel)])
  (def compiled
    (or (get device-kernel-cache key)
        (let [fresh (kernel/compile owner kernel)]
          (put device-kernel-cache key fresh)
          fresh)))
  (kernel/launch compiled queue bindings))

(defn- opencl-owner
  [value]
  (def owner (engine value))
  (when (= "opencl" (compute/engine-name owner)) owner))

(defn- device-reduce
  [x kernels]
  (when-let [owner (opencl-owner x)
             kernel (get kernels (dtype x))]
    (def result (compute/alloc owner (dtype x) [1]))
    (def queue (compute/queue owner))
    (defer (do (compute/close-queue queue)
               (compute/close result))
      (def event
        (launch-device-kernel owner kernel queue
                              {:n (dim x) :x (x :view) :result result}))
      (compute/wait event)
      (compute/close-event event)
      (compute/get result 0))))

(defn sum
  "Return the sum of the entries of a vector as a host number.

  On OpenCL engines :f32 and :f64 vectors reduce on the device through
  kernel-0; other dtypes and engines reduce through synchronous logical
  entry reads."
  [x]
  (or (device-reduce x {:f32 device-sum-f32 :f64 device-sum-f64})
      (reduce-entries x + 0)))

(defn asum
  "Return the sum of the absolute entry values of a vector as a host number.

  On OpenCL engines :f32 and :f64 vectors reduce on the device through
  the abs admitted at the kernel-0.1 gate."
  [x]
  (or (device-reduce x {:f32 device-asum-f32 :f64 device-asum-f64})
      (reduce-entries x (fn [accumulator value] (+ accumulator (math/abs value))) 0)))

(defn nrm2
  "Return the Euclidean norm of a vector as a host number.

  On OpenCL engines the sum of squares reduces on the device through
  kernel-0 with the square root taken on the host."
  [x]
  (math/sqrt
    (or (device-reduce x {:f32 device-square-sum-f32
                          :f64 device-square-sum-f64})
        (reduce-entries x (fn [accumulator value] (+ accumulator (* value value))) 0))))

(defn amax
  "Return the largest absolute entry value of a vector as a host number.

  An empty vector has amax 0. On OpenCL engines :f32 and :f64 vectors
  reduce on the device through the abs and max admitted at the
  kernel-0.1 gate."
  [x]
  (or (device-reduce x {:f32 device-amax-f32 :f64 device-amax-f64})
      (reduce-entries x (fn [accumulator value] (max accumulator (math/abs value))) 0)))

(defn- require-one-engine
  [values operation]
  (def identity (compute/engine-id (engine (first values))))
  (each value values
    (unless (= identity (compute/engine-id (engine value)))
      (errorf "%s requires every argument on one engine" operation))))

(defn mv!
  "Compute `y = alpha*A*x + beta*y` over logical entries in place and
  return `y`.

  `a` may have any structure; the structured loops read only stored
  entries. When `beta` is 0 the previous contents of `y` are never read.
  All three values must share one engine and dtype, the dtype must be one
  the engine declares for numerical operations, and `y` must not share
  storage with `a` or `x`.

  On OpenCL engines :ge and :gd multiplication executes on the device
  through kernel-0; :tr and :sy run the host oracle loops until a client
  justifies their device kernels."
  [y alpha a x beta]
  (require-vector y)
  (require-matrix a)
  (require-vector x)
  (def m (mrows a))
  (def n (ncols a))
  (unless (= n (dim x))
    (errorf "mv! needs %v entries in x for %v matrix columns" n (dim x)))
  (unless (= m (dim y))
    (errorf "mv! needs %v entries in y for %v matrix rows" m (dim y)))
  (def dt (dtype a))
  (unless (and (= dt (dtype x)) (= dt (dtype y)))
    (error "mv! requires one dtype across y, a, and x"))
  (require-one-engine [a x y] "mv!")
  (unless (compute/supports? (engine a) :dot dt)
    (errorf "engine does not declare numerical operations for %v" dt))
  (def y-storage (compute/storage-id (y :view)))
  (when (or (= y-storage (compute/storage-id (a :view)))
            (= y-storage (compute/storage-id (x :view))))
    (error "mv! destination must not share storage with a or x"))
  (def device-owner (opencl-owner a))
  (def device-kernel
    (when device-owner
      (get-in {:ge {:f32 device-mv-f32 :f64 device-mv-f64}
               :gd {:f32 device-mv-gd-f32 :f64 device-mv-gd-f64}}
              [(a :structure) dt])))
  (if device-kernel
    (do
      (when (= beta 0) (compute/fill! (y :view) 0))
      (def queue (compute/queue device-owner))
      (defer (compute/close-queue queue)
        (def bindings
          (if (= :gd (a :structure))
            {:n n :alpha alpha :beta beta
             :a (a :view) :x (x :view) :y (y :view)}
            {:m m :n n :alpha alpha :beta beta
             :a (a :view) :x (x :view) :y (y :view)}))
        (def event (launch-device-kernel device-owner device-kernel queue bindings))
        (compute/wait event)
        (compute/close-event event)))
    (do
      (def dense (compute/to-array (a :view)))
      (def xs (compute/to-array (x :view)))
      (def ys (if (= beta 0) nil (compute/to-array (y :view))))
      (defn emit [i accumulator]
        (compute/put! (y :view) i
                      (+ (* alpha accumulator)
                         (if ys (* beta (ys i)) 0))))
      (case (a :structure)
        :ge
        (loop [i :range [0 m]]
          (var accumulator 0)
          (loop [j :range [0 n]]
            (+= accumulator (* (dense (+ (* i n) j)) (xs j))))
          (emit i accumulator))

        :tr
        (let [lower (= :lower (a :uplo))
              unit (= :unit (a :diag))]
          (loop [i :range [0 m]]
            (var accumulator (if unit (xs i) 0))
            (def start (if lower 0 (if unit (+ i 1) i)))
            (def end (if lower (if unit i (+ i 1)) n))
            (loop [j :range [start end]]
              (+= accumulator (* (dense (+ (* i n) j)) (xs j))))
            (emit i accumulator)))

        :sy
        (let [lower (= :lower (a :uplo))
              accumulators (array/new-filled m 0)]
          (loop [i :range [0 m]]
            (def start (if lower 0 i))
            (def end (if lower (+ i 1) n))
            (loop [j :range [start end]]
              (def value (dense (+ (* i n) j)))
              (put accumulators i (+ (accumulators i) (* value (xs j))))
              (unless (= i j)
                (put accumulators j (+ (accumulators j) (* value (xs i)))))))
          (loop [i :range [0 m]]
            (emit i (accumulators i))))

        :gd
        (loop [i :range [0 m]]
          (emit i (* (dense (+ (* i n) i)) (xs i)))))))
  y)

(defn mv
  "Return `A*x` as a fresh vector allocated on the engine of `a`.

  The result is always a plain :vctr; structure is an input optimization,
  never inferred on outputs."
  [a x]
  (require-matrix a)
  (def result
    {:gp/linalg true :structure :vctr
     :view (compute/alloc (engine a) (dtype a) [(mrows a)])})
  (mv! result 1 a x 0))

(defn- dense-ge
  [value]
  (if (= :ge (value :structure))
    value
    (ge (engine value) (dtype value) (mrows value) (ncols value)
        (to-array value))))

(defn mm
  "Return the matrix product `A*B` as a fresh :ge matrix.

  Both operands must share one native engine and a dtype the engine
  declares for numerical operations. Structured operands are logically
  densified before dispatching to the engines' native matrix
  multiplication; structure-exploiting multiplication waits for a client.
  The result is always :ge — structure is never inferred on outputs."
  [a b]
  (require-matrix a)
  (require-matrix b)
  (require-one-engine [a b] "mm")
  (def dt (dtype a))
  (unless (= dt (dtype b))
    (error "mm requires one dtype across a and b"))
  (unless (compute/supports? (engine a) :mm dt)
    (errorf "engine does not declare numerical operations for %v" dt))
  {:gp/linalg true :structure :ge
   :view (compute/mm ((dense-ge a) :view) ((dense-ge b) :view))})

# linalg-1, opened by the Kalman gain in gp/bayes: exactly the
# factorization and solve that client demands, as host oracles.

(def- float-dtypes {:f32 true :f64 true})

(defn cholesky
  "Return the lower :tr Cholesky factor L of a symmetric
  positive-definite matrix, with `L*Lᵀ` equal to the logical contents.

  Reads the logical lower triangle on the host — the linalg-1 oracle
  admitted for the Kalman gain. Requires a square matrix with a float
  dtype; a non-positive pivot means the matrix is not positive definite
  and is an error."
  [a]
  (require-matrix a)
  (def n (mrows a))
  (unless (= n (ncols a)) (error "cholesky requires a square matrix"))
  (unless (get float-dtypes (dtype a))
    (error "cholesky requires a :f32 or :f64 matrix"))
  (def dense (to-array a))
  (def factor (array/new-filled (* n n) 0))
  (loop [i :range [0 n]]
    (loop [j :range [0 (+ i 1)]]
      (var accumulator 0)
      (loop [k :range [0 j]]
        (+= accumulator (* (factor (+ (* i n) k)) (factor (+ (* j n) k)))))
      (if (= i j)
        (let [pivot (- (dense (+ (* i n) i)) accumulator)]
          (when (<= pivot 0)
            (error "matrix is not positive definite"))
          (put factor (+ (* i n) i) (math/sqrt pivot)))
        (put factor (+ (* i n) j)
             (/ (- (dense (+ (* i n) j)) accumulator)
                (factor (+ (* j n) j)))))))
  (tr (engine a) (dtype a) n factor))

(defn solve
  "Return `x` solving `T x = b` for a :tr matrix by forward or back
  substitution on the host, honoring the stored triangle and an
  implicit :unit diagonal.

  The result is a fresh :vctr on the engine of `t`. A zero diagonal
  entry means `T` is singular and is an error."
  [t b]
  (require-linalg t)
  (unless (= :tr (t :structure)) (error "solve requires a :tr matrix"))
  (require-vector b)
  (def n (mrows t))
  (unless (= n (dim b))
    (errorf "solve needs %v entries in b for %v matrix rows" n n))
  (unless (= (dtype t) (dtype b))
    (error "solve requires one dtype across t and b"))
  (unless (get float-dtypes (dtype t))
    (error "solve requires a :f32 or :f64 matrix"))
  (def dense (to-array t))
  (def rhs (compute/to-array (b :view)))
  (def result (array/new-filled n 0))
  (def lower (= :lower (t :uplo)))
  (each i (if lower (range n) (reverse (range n)))
    (var accumulator (rhs i))
    (if lower
      (loop [j :range [0 i]]
        (-= accumulator (* (dense (+ (* i n) j)) (result j))))
      (loop [j :range [(+ i 1) n]]
        (-= accumulator (* (dense (+ (* i n) j)) (result j)))))
    (def diagonal (dense (+ (* i n) i)))
    (when (= 0 diagonal) (error "triangular matrix is singular"))
    (put result i (/ accumulator diagonal)))
  (vctr (engine t) (dtype t) result))
