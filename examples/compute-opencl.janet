(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)

(unless (opencl/available?)
  (error "No OpenCL platform is available"))

(pp (opencl/devices))

(def cpu (cpp/engine))
(def gpu (opencl/engine))
(def host (compute/vector cpu :f32 [1 2 3 4]))
(def device (compute/transfer gpu host))
(def queue (compute/queue gpu))

(def scaled (compute/enqueue-scal! queue device 10))
(def [energy ready] (compute/enqueue-dot queue device device scaled))

(compute/wait ready)
(pp (compute/to-array (compute/transfer cpu device)))
(pp (compute/to-array (compute/transfer cpu energy)))
