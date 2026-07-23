(import ./native :as native)

(defn available?
  "Return true when the system exposes at least one OpenCL platform."
  []
  (native/opencl-available?))

(defn platforms
  "Return the available OpenCL platforms and their devices."
  []
  (array
    ;(seq [platform :range [0 (native/opencl-platform-count)]]
       {:index platform
        :name (native/opencl-platform-name platform)
        :devices
        (array
          ;(seq [device :range [0 (native/opencl-device-count platform)]]
             {:index device
              :platform platform
              :name (native/opencl-device-name platform device)
              :vendor (native/opencl-device-vendor platform device)
              :version (native/opencl-device-version platform device)
              :fp64? (native/opencl-device-fp64? platform device)
              :global-memory
              (native/opencl-device-global-memory platform device)}))})))

(defn devices
  "Return a flat array of available OpenCL device descriptions."
  []
  (array
    ;(seq [platform :in (platforms)
           device :in (platform :devices)]
       device)))

(defn engine
  "Create an engine for an OpenCL platform and device index."
  [&named platform device]
  (default platform 0)
  (default device 0)
  (native/new-opencl-engine platform device))
