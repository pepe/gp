(import gp/compute)

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
