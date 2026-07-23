(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)

(start-suite "Compute documentation")
(assert-docs "gp/compute")
(assert-docs "gp/compute/cpp")
(end-suite)

(start-suite "Compute C++ engine")

(def engine (cpp/engine))
(assert (= "cpp" (compute/engine-name engine)) "engine name")
(assert (compute/sync engine) "synchronous engine")

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
