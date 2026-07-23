# Build the dependency-free C++ reference compute engine.

(def- windows? (= :windows (os/which)))
(def- include-flags [(string (if windows? "/I" "-I") "src")])

(declare-native
  :name "gp/compute/cpp-native"
  :source @["cjanet/compute.janet" "src/compute-helper.cpp"]
  :cflags include-flags
  :c++flags include-flags
  :deps ["src/compute-helper.h"]
  :c++-std 17
  :nostatic true)
