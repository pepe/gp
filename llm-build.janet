# Build the pinned llama.cpp submodule as a static CPU-only dependency, then
# link it into gp's private Janet native module. No llama runtime DLL is needed.

(def- llama-source "vendor/llama.cpp")
(def- windows? (= :windows (os/which)))
(def- build-type (dyn *build-type* :develop))
(def- cmake-config (if (in {:release true :native true} build-type) "Release" "Debug"))
(def- llama-build
  (if (= cmake-config "Release") "_build/llama-cpu-release" "_build/llama-cpu-debug"))
(def- config-dir (if windows? cmake-config ""))
(def- llama-lib
  (string/join [llama-build "src" ;(if windows? [config-dir] [])
                (if windows? "llama.lib" "libllama.a")] "/"))
(def- ggml-dir (string/join [llama-build "ggml" "src" config-dir] "/"))
(defn- ggml-lib [name]
  (string ggml-dir "/" (if windows? (string name ".lib") (string "lib" name ".a"))))

(rule llama-lib [(string llama-source "/CMakeLists.txt") "src/llama.version"]
  (print "building pinned llama.cpp CPU runtime...")
  (flush)
  (exec-fail
    "cmake" "-S" llama-source "-B" llama-build
    "-DBUILD_SHARED_LIBS=OFF"
    "-DLLAMA_BUILD_COMMON=OFF"
    "-DLLAMA_BUILD_TESTS=OFF"
    "-DLLAMA_BUILD_TOOLS=OFF"
    "-DLLAMA_BUILD_EXAMPLES=OFF"
    "-DLLAMA_BUILD_SERVER=OFF"
    "-DLLAMA_BUILD_APP=OFF"
    "-DGGML_NATIVE=OFF"
    "-DGGML_OPENMP=OFF"
    "-DGGML_BLAS=OFF"
    "-DGGML_ACCELERATE=OFF"
    "-DGGML_CUDA=OFF"
    "-DGGML_HIP=OFF"
    "-DGGML_METAL=OFF"
    "-DGGML_OPENCL=OFF"
    "-DGGML_RPC=OFF"
    "-DGGML_SYCL=OFF"
    "-DGGML_VULKAN=OFF"
    (string "-DCMAKE_BUILD_TYPE=" cmake-config))
  (exec-fail "cmake" "--build" llama-build "--config" cmake-config "--target" "llama" "-j" "4"))

(def- include-dirs
  [(string llama-source "/include")
   (string llama-source "/ggml/include")
   "src"])
(def- include-flags
  (seq [dir :in include-dirs]
    (string (if windows? "/I" "-I") dir)))
(def- llama-libraries
  [llama-lib
   (ggml-lib "ggml")
   (ggml-lib "ggml-cpu")
   (ggml-lib "ggml-base")
   ;(if windows? ["Advapi32.lib"] [])])

(declare-native
  :name "gp/llm-native"
  :source @["cjanet/llm.janet" "src/llm-helper.cpp"]
  :cflags include-flags
  :c++flags include-flags
  :deps [llama-lib "src/llm-helper.h"]
  :msvc-libs (if windows? llama-libraries [])
  :static-libs (if windows? [] llama-libraries)
  :smart-libs true
  :c++-std 17
  :nostatic true)
