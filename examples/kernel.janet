(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)
(import gp/kernel)

(kernel/defkernel saxpy
  [n:i32
   alpha:f32
   (x (buffer :f32 [n] :read))
   (y (buffer :f32 [n] :read-write))]
  (parallel [i 0 n]
    (store! y [i]
      (+ (* alpha (load x [i]))
         (load y [i])))))

(def engine (cpp/engine))
(def x (compute/vector engine :f32 [1 2 3]))
(def y (compute/vector engine :f32 [10 20 30]))

(kernel/run! saxpy {:n 3 :alpha 2 :x x :y y})
(pp (compute/to-array y))
(pp (kernel/ir saxpy))

(when (opencl/available?)
  (def device (opencl/engine))
  (def queue (compute/queue device))
  (def device-x (compute/vector device :f32 [1 2 3]))
  (def device-y (compute/vector device :f32 [10 20 30]))
  (def compiled (kernel/compile device saxpy))
  (print (kernel/source compiled))
  (compute/wait
    (kernel/launch compiled queue
                   {:n 3 :alpha 2 :x device-x :y device-y}))
  (pp (compute/to-array device-y)))
