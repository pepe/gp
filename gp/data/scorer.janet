(use spork/misc)
(import gp/data/fuzzy :prefix "" :export true)

(defn score-n-order-positions
  ```
  Takes `needle` with the fuzzy search and `hays` with collection of the tuples
  of the form `[string score [positions]]` it then fuzzy scores string and
  returns the collection of the same shape, but only with the results 
  that matched and with updated `score` and `positions`.
  ```
  [needle hays]
  (do-def res @[]
          (loop [[hay _ _] :in hays
                 :let [sc (score needle hay)]
                 :when (and sc (> sc score-min))]
            (def sct [hay sc (positions needle hay)])
            (if-let [bi (find-index |(> sc ($ 1)) res)]
              (array/insert res bi sct)
              (array/push res sct)))))
