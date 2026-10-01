(use spork/declare-cc spork/path spork/sh spork/cc)

(declare-project :name "gp")

(declare-source :source ["gp"])

(declare-native :name "gp/ownership" :source @["src/ownership.c"])

(declare-native
  :name "gp/codec"
  :source @["cjanet/codec.janet"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["cjanet/fuzzy.janet"])

(declare-native
  :name "gp/net/curi"
  :source @["cjanet/curi.janet"])

(declare-native
  :name "gp/qr-native"
  :source @["cjanet/qr-codegen.janet" "src/qrcodegen.c"])

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

(declare-binscript
  :main "bin/gpgen"
  :is-janet true)
