(import gp/compute)
(import gp/compute/cpp)

(def engine (cpp/engine))
(def a (compute/matrix engine :f32 [2 3] [1 2 3
                                                 4 5 6]))
(def b (compute/matrix engine :f32 [3 2] [7 8
                                                 9 10
                                                 11 12]))
(def product (compute/mm a b))

(pp (compute/shape product))
(pp (compute/to-array product))
