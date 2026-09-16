(import gp/ownership)
(import jhydro)

(defn write
  "Stages bytes beside a destination, closes them, then atomically replaces it."
  [destination bytes &opt mode]
  (def staged (string destination ".pending-" (jhydro/util/bin2hex (os/cryptorand 12))))
  (defer (when (os/stat staged) (os/rm staged))
    (with [file (file/open staged :wb)]
      (:write file bytes)
      (:flush file))
    (when mode (os/chmod staged mode))
    (ownership/replace staged destination))
  destination)

(defn copy
  "Installs a complete artifact without truncating an executable already in use."
  [source destination &opt mode]
  (write destination (slurp source) mode))
