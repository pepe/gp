# Build the C++ reference engine and dynamically loaded OpenCL backend.

(def- windows? (= :windows (os/which)))
(def- include-flags
  (seq [dir :in ["src" "vendor/OpenCL-Headers"]]
    (string (if windows? "/I" "-I") dir)))

(declare-native
  :name "gp/compute/native"
  :source @["cjanet/compute.janet"
            "src/compute-helper.cpp"
            "src/opencl-helper.cpp"]
  :cflags include-flags
  :c++flags include-flags
  :deps ["src/compute-helper.h"
         "src/compute-internal.hpp"
         "src/opencl-headers.version"
         "vendor/OpenCL-Headers/CL/cl.h"]
  :dynamic-libs (if windows? [] ["-ldl"])
  :c++-std 17)
