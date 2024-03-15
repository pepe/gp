# This is example of setting up the registry for validation.
# It simplifies the creation of the schema and resolving
# the blockers from analysis.

(use /gp/data/schema)

(def data {:name "" :age -1})


(def?! present-name
  {:name present-string?})

(def?! age-pos-number
  {:age [all number? pos?]})

(def?! schema 
  present-name? age-pos-number?)

(unless (schema? data)
  (printf "Data %q is not valid with schema %q" data schema?)
  (print "Analysing")
  (def analysis (schema! data))
  (loop [p :in analysis]
    (case (type p)
      :tuple
      (printf "does not comply to %q" (p 1)))))
