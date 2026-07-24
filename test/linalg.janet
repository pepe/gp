(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)
(import gp/linalg)

(start-suite "Linalg documentation")
(assert-docs "gp/linalg")
(end-suite)

(def host (cpp/engine))

(start-suite "Linalg vectors")

(def x (linalg/vctr host :f32 [1 2 3]))
(assert (linalg/linalg? x) "linalg value")
(assert (linalg/vector? x) "vector predicate")
(assert (not (linalg/matrix? x)) "vector is not a matrix")
(assert (not (linalg/linalg? {:structure :vctr})) "foreign struct rejected")
(assert (= :vctr (linalg/structure x)) "vector structure")
(assert (= :f32 (linalg/dtype x)) "vector dtype")
(assert (= "cpp" (compute/engine-name (linalg/engine x))) "vector engine")
(assert (= 3 (linalg/dim x)) "vector dimension")
(assert (= 2 (linalg/entry x 1)) "vector entry")
(linalg/entry! x 1 9)
(assert (deep= @[1 9 3] (linalg/to-array x)) "vector write")
(assert-error "vector entry takes one index" (linalg/entry x 1 2))
(assert-error "vector bounds" (linalg/entry x 3))
(assert-error "vector negative bounds" (linalg/entry x -1))
(assert-error "dim rejects matrices" (linalg/dim (linalg/ge host :f32 1 1 [1])))

(def sub (linalg/subvector x 1 2))
(assert (linalg/vector? sub) "subvector value")
(assert (= 2 (linalg/dim sub)) "subvector dimension")
(assert (= (compute/storage-id (linalg/view x))
           (compute/storage-id (linalg/view sub)))
        "subvector shares storage")
(linalg/entry! sub 0 7)
(assert (deep= @[1 7 3] (linalg/to-array x)) "subvector writes through")

(end-suite)

(start-suite "Linalg general matrices")

(def a (linalg/ge host :f32 2 3 [1 2 3 4 5 6]))
(assert (linalg/matrix? a) "matrix predicate")
(assert (= :ge (linalg/structure a)) "general structure")
(assert (= 2 (linalg/mrows a)) "matrix rows")
(assert (= 3 (linalg/ncols a)) "matrix columns")
(assert (= 6 (linalg/entry a 1 2)) "matrix entry")
(assert-error "matrix entry takes two indexes" (linalg/entry a 1))
(assert-error "matrix row bounds" (linalg/entry a 2 0))
(assert-error "matrix column bounds" (linalg/entry a 0 3))
(assert-error "uplo rejects general matrices" (linalg/uplo a))

(def at (linalg/trans a))
(assert (= :ge (linalg/structure at)) "transpose stays general")
(assert (= 3 (linalg/mrows at)) "transposed rows")
(assert (= 2 (linalg/ncols at)) "transposed columns")
(assert (= 6 (linalg/entry at 2 1)) "transposed entry")
(assert (= (compute/storage-id (linalg/view a))
           (compute/storage-id (linalg/view at)))
        "transpose is zero-copy")
(assert-error "trans rejects vectors" (linalg/trans x))

(assert (deep= @[1 2 3] (linalg/to-array (linalg/row a 0))) "row view")
(assert (deep= @[2 5] (linalg/to-array (linalg/col a 1))) "column view")
(linalg/entry! (linalg/col a 1) 0 20)
(assert (= 20 (linalg/entry a 0 1)) "column view writes through")
(assert-error "row bounds" (linalg/row a 2))
(assert-error "column bounds" (linalg/col a 3))

(end-suite)

(start-suite "Linalg structured matrices")

(def t (linalg/tr host :f32 2 [1 99 2 3]))
(assert (= :tr (linalg/structure t)) "triangular structure")
(assert (= :lower (linalg/uplo t)) "default uplo")
(assert (not (linalg/unit-diag? t)) "default diagonal")
(assert (= 0 (linalg/entry t 0 1)) "unstored triangle reads zero")
(assert (= 2 (linalg/entry t 1 0)) "stored triangle reads storage")
(assert (deep= @[1 0 2 3] (linalg/to-array t)) "logical triangular contents")
(assert-error "unstored triangle rejects writes" (linalg/entry! t 0 1 5))
(assert-error "invalid uplo" (linalg/tr host :f32 2 [1 0 2 3] :diagonal))
(assert-error "invalid diag" (linalg/tr host :f32 2 [1 0 2 3] :lower :odd))

(def unit (linalg/tr host :f32 2 [99 0 2 99] :lower :unit))
(assert (linalg/unit-diag? unit) "unit diagonal predicate")
(assert (= 1 (linalg/entry unit 0 0)) "unit diagonal reads one")
(assert (deep= @[1 0 2 1] (linalg/to-array unit)) "logical unit contents")
(assert-error "unit diagonal rejects writes" (linalg/entry! unit 0 0 5))

(def tt (linalg/trans t))
(assert (= :upper (linalg/uplo tt)) "transpose flips the triangle")
(assert (= 2 (linalg/entry tt 0 1)) "transposed stored entry")
(assert (= 0 (linalg/entry tt 1 0)) "transposed implicit zero")
(assert (deep= @[1 2 0 3] (linalg/to-array tt)) "logical transposed contents")

(def s (linalg/sy host :f32 2 [1 99 2 3]))
(assert (= :sy (linalg/structure s)) "symmetric structure")
(assert (= 2 (linalg/entry s 0 1)) "mirrored entry")
(assert (deep= @[1 2 2 3] (linalg/to-array s)) "logical symmetric contents")
(assert-error "mirror rejects writes" (linalg/entry! s 0 1 5))
(linalg/entry! s 1 0 4)
(assert (= 4 (linalg/entry s 0 1)) "stored write updates the mirror")
(assert (= s (linalg/trans s)) "symmetric matrix is its own transpose")

(def d (linalg/gd host :f32 3 [1 2 3]))
(assert (= :gd (linalg/structure d)) "diagonal structure")
(assert (= 3 (linalg/mrows d)) "diagonal rows")
(assert (= 2 (linalg/entry d 1 1)) "diagonal entry")
(assert (= 0 (linalg/entry d 0 2)) "off-diagonal reads zero")
(assert (deep= @[1 0 0 0 2 0 0 0 3] (linalg/to-array d))
        "logical diagonal contents")
(assert-error "off-diagonal rejects writes" (linalg/entry! d 0 1 5))
(assert-error "diagonal length must match" (linalg/gd host :f32 3 [1 2]))
(assert (= d (linalg/trans d)) "diagonal matrix is its own transpose")
(assert-error "row views need general structure" (linalg/row t 0))
(assert-error "unit-diag? rejects other structures" (linalg/unit-diag? s))

(end-suite)

(start-suite "Linalg transfer")

(def moved (linalg/transfer host t))
(assert (= :tr (linalg/structure moved)) "transfer preserves structure")
(assert (= :lower (linalg/uplo moved)) "transfer preserves uplo")
(assert (not (linalg/unit-diag? moved)) "transfer preserves diag")
(assert (deep= (linalg/to-array t) (linalg/to-array moved))
        "transfer preserves contents")
(assert (not= (compute/storage-id (linalg/view t))
              (compute/storage-id (linalg/view moved)))
        "transfer copies storage")

(def moved-tt (linalg/transfer host tt))
(assert (= :upper (linalg/uplo moved-tt))
        "transferred transpose keeps the flipped triangle")
(assert (deep= (linalg/to-array tt) (linalg/to-array moved-tt))
        "transferred transpose preserves logical contents")

(when (opencl/available?)
  (def gpu (opencl/engine))
  (def device-a (linalg/transfer gpu a))
  (assert (= "opencl" (compute/engine-name (linalg/engine device-a)))
          "device value engine")
  (assert (= :ge (linalg/structure device-a)) "device structure")
  (assert (deep= (linalg/to-array a) (linalg/to-array device-a))
          "device contents")
  (def device-s (linalg/transfer gpu s))
  (assert (= :lower (linalg/uplo device-s)) "device uplo")
  (assert (deep= (linalg/to-array s) (linalg/to-array device-s))
          "device symmetric logical contents")
  (assert (= 4 (linalg/entry device-s 0 1)) "device mirrored entry")
  (def round-trip (linalg/transfer host device-a))
  (assert (deep= (linalg/to-array a) (linalg/to-array round-trip))
          "round trip"))

(end-suite)

(start-suite "Linalg level-1 vectors")

(def v (linalg/vctr host :f32 [1 -2 3]))
(assert (= 2 (linalg/sum v)) "vector sum")
(assert (= 6 (linalg/asum v)) "vector asum")
(assert (= (math/sqrt 14) (linalg/nrm2 v)) "vector nrm2")
(assert (= 3 (linalg/amax v)) "vector amax")
(def w (linalg/vctr host :f32 [4 5 6]))
(assert (= 12 (linalg/dot v w)) "vector dot")

(linalg/scal! v 2)
(assert (deep= @[2 -4 6] (linalg/to-array v)) "vector scal!")
(assert (= v (linalg/axpy! v 0.5 w)) "axpy! returns the destination")
(assert (deep= @[4 -1.5 9] (linalg/to-array v)) "vector axpy!")
(def copied (linalg/vctr host :f32 [0 0 0]))
(linalg/copy! copied w)
(assert (deep= @[4 5 6] (linalg/to-array copied)) "vector copy!")

(def integers (linalg/vctr host :i32 [3 -4 5]))
(assert (= 4 (linalg/sum integers)) "i32 sum")
(assert (= 12 (linalg/asum integers)) "i32 asum")
(assert (= 5 (linalg/amax integers)) "i32 amax")
(assert (= 50 (linalg/dot integers integers)) "i32 dot on the C++ oracle")

(assert-error "dot rejects matrices" (linalg/dot v a))
(assert-error "reductions reject matrices" (linalg/sum a))
(assert-error "copy! rejects structure mismatch" (linalg/copy! copied a))
(assert-error "copy! rejects dtype mismatch" (linalg/copy! copied integers))

(end-suite)

(start-suite "Linalg level-1 matrices")

(def scaled-tr (linalg/tr host :f32 2 [1 99 2 3]))
(linalg/scal! scaled-tr 2)
(assert (deep= @[2 0 4 6] (linalg/to-array scaled-tr))
        "triangular scal! stays logical")
(def scaled-gd (linalg/gd host :f32 3 [1 2 3]))
(linalg/scal! scaled-gd 2)
(assert (deep= @[2 0 0 0 4 0 0 0 6] (linalg/to-array scaled-gd))
        "diagonal scal!")
(def scaled-sy (linalg/sy host :f32 2 [1 99 2 3]))
(linalg/scal! scaled-sy 3)
(assert (deep= @[3 6 6 9] (linalg/to-array scaled-sy)) "symmetric scal!")
(assert-error "unit triangle rejects scal!"
              (linalg/scal! (linalg/tr host :f32 2 [1 0 2 3] :lower :unit) 2))

(def tr-x (linalg/tr host :f32 2 [1 99 2 3]))
(def tr-y (linalg/tr host :f32 2 [10 99 20 30]))
(linalg/axpy! tr-y 2 tr-x)
(assert (deep= @[12 0 24 36] (linalg/to-array tr-y)) "triangular axpy!")
(assert-error "axpy! rejects mismatched triangles"
              (linalg/axpy! tr-y 1 (linalg/tr host :f32 2 [1 0 2 3] :upper)))
(assert-error "axpy! rejects mismatched diagonal kinds"
              (linalg/axpy! tr-y 1 (linalg/tr host :f32 2 [1 0 2 3] :lower :unit)))
(assert-error "axpy! rejects unit triangles"
              (linalg/axpy! (linalg/tr host :f32 2 [1 0 2 3] :lower :unit)
                            1
                            (linalg/tr host :f32 2 [1 0 2 3] :lower :unit)))

(def tr-copy (linalg/tr host :f32 2 [0 0 0 0]))
(linalg/copy! tr-copy tr-x)
(assert (deep= (linalg/to-array tr-x) (linalg/to-array tr-copy))
        "triangular copy!")
(assert-error "copy! rejects mismatched triangles"
              (linalg/copy! tr-copy (linalg/tr host :f32 2 [1 0 2 3] :upper)))
(assert-error "copy! rejects mismatched symmetric triangles"
              (linalg/copy! (linalg/sy host :f32 2 [1 0 2 3])
                            (linalg/sy host :f32 2 [1 0 2 3] :upper)))

(def dense (linalg/ge host :f32 2 3 [1 2 3 4 5 6]))
(def dense-t (linalg/trans (linalg/ge host :f32 3 2 [10 20 30 40 50 60])))
(linalg/axpy! dense 1 dense-t)
(assert (deep= @[11 32 53 24 45 66] (linalg/to-array dense))
        "general axpy! over a strided transpose")

(end-suite)

(start-suite "Linalg level-1 OpenCL")

(when (opencl/available?)
  (def gpu (opencl/engine))
  (def device-v (linalg/transfer gpu (linalg/vctr host :f32 [1 -2 3])))
  (def device-w (linalg/transfer gpu (linalg/vctr host :f32 [4 5 6])))
  (assert (= 12 (linalg/dot device-v device-w)) "device dot")
  (assert (= 2 (linalg/sum device-v)) "device sum")
  (assert (= 6 (linalg/asum device-v)) "device asum")
  (assert (= (math/sqrt 14) (linalg/nrm2 device-v)) "device nrm2")
  (assert (= 3 (linalg/amax device-v)) "device amax")
  (linalg/scal! device-v 2)
  (linalg/axpy! device-v 0.5 device-w)
  (assert (deep= @[4 -1.5 9] (linalg/to-array device-v)) "device scal!/axpy!")
  (def device-tr (linalg/transfer gpu (linalg/tr host :f32 2 [1 99 2 3])))
  (linalg/scal! device-tr 2)
  (assert (deep= @[2 0 4 6] (linalg/to-array device-tr))
          "device triangular scal! stays logical")
  (def device-integers (linalg/transfer gpu (linalg/vctr host :i32 [3 -4 5])))
  (assert (= 4 (linalg/sum device-integers))
          "device i32 reduction reads logically")
  (assert-error "device i32 numerical policy is inherited"
                (linalg/dot device-integers device-integers))
  (assert-error "no implicit transfer in axpy!"
                (linalg/axpy! device-w 1 (linalg/vctr host :f32 [1 2 3]))))

(end-suite)

(start-suite "Linalg matrix-vector multiplication")

(defn densify
  [matrix]
  (linalg/ge (linalg/engine matrix) (linalg/dtype matrix)
             (linalg/mrows matrix) (linalg/ncols matrix)
             (linalg/to-array matrix)))

(defn assert-mv-oracle
  [matrix x message]
  (assert (deep= (linalg/to-array (linalg/mv (densify matrix) x))
                 (linalg/to-array (linalg/mv matrix x)))
          message))

(def mv-a (linalg/ge host :f32 2 3 [1 2 3 4 5 6]))
(def mv-x (linalg/vctr host :f32 [1 2 3]))
(def mv-result (linalg/mv mv-a mv-x))
(assert (linalg/vector? mv-result) "mv returns a vector")
(assert (deep= @[14 32] (linalg/to-array mv-result)) "general mv")
(def mv-y (linalg/vctr host :f32 [10 20]))
(assert (= mv-y (linalg/mv! mv-y 2 mv-a mv-x 3)) "mv! returns the destination")
(assert (deep= @[58 124] (linalg/to-array mv-y)) "general mv! with beta")

(def mv-at (linalg/trans mv-a))
(assert (deep= @[9 12 15]
               (linalg/to-array (linalg/mv mv-at (linalg/vctr host :f32 [1 2]))))
        "transposed mv over strided storage")

(def mv-x2 (linalg/vctr host :f32 [4 5]))
(def lower-tr (linalg/tr host :f32 2 [1 99 2 3]))
(assert (deep= @[4 23] (linalg/to-array (linalg/mv lower-tr mv-x2)))
        "lower triangular mv reads only the stored triangle")
(assert-mv-oracle lower-tr mv-x2 "lower triangular mv matches the dense oracle")
(def unit-tr (linalg/tr host :f32 2 [99 0 2 99] :lower :unit))
(assert (deep= @[4 13] (linalg/to-array (linalg/mv unit-tr mv-x2)))
        "unit triangular mv adds the implicit diagonal")
(assert-mv-oracle unit-tr mv-x2 "unit triangular mv matches the dense oracle")
(def upper-tr (linalg/trans lower-tr))
(assert (deep= @[14 15] (linalg/to-array (linalg/mv upper-tr mv-x2)))
        "upper triangular mv")
(assert-mv-oracle upper-tr mv-x2 "upper triangular mv matches the dense oracle")
(assert-mv-oracle (linalg/trans unit-tr) mv-x2
                  "upper unit triangular mv matches the dense oracle")

(def mv-sy (linalg/sy host :f32 2 [1 99 2 3]))
(assert (deep= @[14 23] (linalg/to-array (linalg/mv mv-sy mv-x2)))
        "symmetric mv accumulates the mirror")
(assert-mv-oracle mv-sy mv-x2 "symmetric mv matches the dense oracle")
(assert-mv-oracle (linalg/sy host :f32 3 [1 2 3 4 5 6 7 8 9] :upper)
                  (linalg/vctr host :f32 [1 2 3])
                  "upper symmetric mv matches the dense oracle")

(def mv-gd (linalg/gd host :f32 3 [1 2 3]))
(assert (deep= @[4 10 18]
               (linalg/to-array (linalg/mv mv-gd (linalg/vctr host :f32 [4 5 6]))))
        "diagonal mv")
(assert-mv-oracle mv-gd (linalg/vctr host :f32 [4 5 6])
                  "diagonal mv matches the dense oracle")

(def mv-i32 (linalg/ge host :i32 2 2 [1 2 3 4]))
(assert (deep= @[17 39]
               (linalg/to-array (linalg/mv mv-i32 (linalg/vctr host :i32 [5 6]))))
        "integer mv on the C++ oracle")

(assert-error "mv! rejects column mismatch"
              (linalg/mv! mv-y 1 mv-a (linalg/vctr host :f32 [1 2]) 0))
(assert-error "mv! rejects row mismatch"
              (linalg/mv! (linalg/vctr host :f32 [1 2 3]) 1 mv-a mv-x 0))
(assert-error "mv! rejects dtype mixing"
              (linalg/mv! mv-y 1 mv-a (linalg/vctr host :f64 [1 2 3]) 0))
(assert-error "mv! rejects a matrix destination" (linalg/mv! mv-a 1 mv-a mv-x 0))
(assert-error "mv! rejects a vector operand" (linalg/mv! mv-y 1 mv-x mv-x 0))
(assert-error "mv! rejects aliased destination and input"
              (linalg/mv! (linalg/subvector mv-x 0 2) 1
                          (linalg/ge host :f32 2 3 [1 2 3 4 5 6]) mv-x 0))

(when (opencl/available?)
  (def gpu (opencl/engine))
  (def device-a (linalg/transfer gpu mv-a))
  (def device-x (linalg/transfer gpu mv-x))
  (def device-result (linalg/mv device-a device-x))
  (assert (= "opencl" (compute/engine-name (linalg/engine device-result)))
          "device mv allocates on the device")
  (assert (deep= @[14 32] (linalg/to-array device-result)) "device mv oracle")
  (def device-y (linalg/transfer gpu (linalg/vctr host :f32 [10 20])))
  (linalg/mv! device-y 2 device-a device-x 3)
  (assert (deep= @[58 124] (linalg/to-array device-y)) "device mv! with beta")
  (assert-error "device integer mv rejected by the capability contract"
                (linalg/mv (linalg/transfer gpu mv-i32)
                           (linalg/transfer gpu (linalg/vctr host :i32 [5 6]))))
  (assert-error "mv! rejects mixed engines"
                (linalg/mv! mv-y 1 device-a device-x 0)))

(end-suite)
