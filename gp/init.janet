(import ./datetime :export true)
(import ./events :export true)
(import ./route :export true)
(import ./utils :export true)
(import ./net :export true)
(import ./data :export true)

(def version "Current library version" ((parse (slurp "bundle/info.jdn")) :version))
