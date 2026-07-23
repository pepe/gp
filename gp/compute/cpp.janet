(import ./native :as native)

(defn engine
  "Create a handle for the synchronous C++ reference compute engine."
  []
  (native/cpp-engine))
