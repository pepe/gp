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

(compute/scal! device 10)
(pp (compute/to-array (compute/transfer cpu device)))
