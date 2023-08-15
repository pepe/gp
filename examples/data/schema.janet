# This is example of setting up the registry for validation.
# It simplifies the creation of the schema and resolving
# the blockers from analysis.

(use /gp/data/schema)

(def data {:name "" :age -1})

(define-registry
  "Schema rules registry"
  :present-name {:name present-string?}
  :age-pos-number {:age [all number? pos?]})

(def schema [table? (registry->schema :present-name
                                      :age-pos-number)])
(def registry (dyn :registry))
(def lookup (invert registry))

(defn pricomply [d e]
  (printf "Data %q does not comply to %q" d e))

(unless ((validator ;schema) data)
  (printf "Data %q is not valid with schema %q" data schema)
  (print "Analysing")
  (def analysis ((analyst ;schema) data))
  (loop [p :in analysis]
    (case (type p)
      :tuple
      (pricomply (p 0) (p 1))
      :struct
      (loop [pi :pairs p
             :let [[d e] pi]]
        (pricomply (data d) (lookup (struct ;pi)))))))
