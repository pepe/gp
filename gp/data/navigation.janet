(use spork/misc ./schema)

# The data navigation module enables traversal of data structures 
# using provided path. The traversal function sets the current base 
# to the initial data structure and moves through the structure 
# according to the specified path points, similar to core get-in functionality. 
# The function returns the latest base after traversing the entire path.

(defn traverse
  ```
  The function constructs a function to traverse a data structure based 
  on the provided `path`, consisting of variadic number of points. 
  Each point can be a function of an arity one, called 
  with the current base, or a key used to access the value.
  Returns a function with arity of one, which takes the data structure 
  to be traversed as its argument.
  ```
  [& path]
  (def compath
    (map
      (fn [p] (if (fn? p) p (fn getter [base] (get base p))))
      path))
  (fn traverse [ds]
    (var base ds)
    (each transfn compath
      (try
        (set base (transfn base))
        ([e f]
          (def prefix (string "Point " (describe transfn) " errored with: "))
          (if (dyn :debug)
            (debug/stacktrace f e prefix)
            (error (string prefix e))))))
    base))

(def => "traverse alias" traverse)

# Points are fundamental units of the path used for traversal.
# This selection is not exhaustive and can serve as educational material.
# Points must be functions and have an arity of one.  
# Functions should return other functions.

(defn >map
  ```
  Returns a function, that maps base with the function `fun` and `args`.
  The function returns the new array as the new base.
  ```
  [fun & args]
  (fn map-fn [base] (map |(fun $ ;args) base)))

(defn >map-get
  ```
  Returns a function, that maps value under `key` from all members 
  of the base.
  The function returns an array of all mapped values.
  ```
  [key]
  (>map get key))

(def >: `>map-get alias` >map-get)

(defn >filter
  ```
  Returns a function, that filters all members of the base
  by the function `fun`.
  ```
  [fun]
  (fn >filter [base] (filter fun base)))

(def >Y `>filter alias` >filter)

(defn >check
  ```
  Returns a function, that checks if `which` members
  of the base conforms to `predicate`.
  ```
  [which predicate]
  (fn >check [base] (which predicate base)))

(def >?? `check alias` >check)

(defn >check-all
  ```
  Returns a function, that checks if `which` for all `predicates` 
  returns true on base
  ```
  [which & predicates]
  (fn >check-all [base] (which |($ base) predicates)))

(defn >limit
  ```
  Returns a function, that limits the number of indexed
  base to `count` members. It retains the base type if possible.
  ```
  [amount]
  (fn >limit [base]
    (if (> (length base) amount)
      ((case (type base)
         :array array/slice
         :buffer buffer/slice
         :symbol symbol/slice
         :keyword keyword/slice
         slice) base 0 amount)
      base)))

(def >n "Alias for limit" >limit)

(defn >collect
  ```
  Returns a function, that collects result of the `fun`
  call with the base as argument to `collected`. The base is unchanged.
  Argument `fun` is optional, if falsy the whole base is collected.
  ```
  [collected &opt fun]
  (fn >collect [base]
    (array/push collected (if fun (fun base) base))
    base))

(def <- `collect alias` >collect)

(defn >merge
  ```
  Returns a function, that merges all tables in base to optional `tab`,
  which defaults to `@{}`.
  ```
  [&opt tab]
  (default tab @{})
  (fn >merged [base] (merge tab ;base)))

(defn >merge-into
  "Returns a function which merges `tab` into the base."
  [tab]
  (fn >merge-into [base] (merge-into base tab)))

(defn >select-keys
  ```
  Returns a function which selects `keys` from the base 
  and returns new table just with them.
  ```
  [& keys]
  (fn >select [i] (select-keys i keys)))

(def >:: `>select-keys alias` >select-keys)

(defn >flatvals
  ```
  Returns a function which flattens the values of each member
  of the base.
  ```
  [base]
  (def res @[])
  (loop [t :in base] (array/push res ;(values t)))
  res)

(defn >put
  ```
  Returns a function, that changes the base under the `key` 
  to a new `value`.
  ```
  [key value]
  (fn >put [base] (put base key value)))

(defn >update
  ```
  Returns the function, that changes the base under the `key` to result
  of running `fun` on its value.
  ```
  [key fun]
  (fn >update [base] (update base key fun)))

(defn >updates
  ```
  Returns the function, that changes the base under the `key` to result
  of running `fun` from `kfns` pairs.
  ```
  [& kfns]
  (fn >updates [base]
    (each [key fun] (partition 2 kfns)
      (update base key fun))
    base))

(defn >clear
  "Returns the function, that clears `keys` of the base"
  [& keyz]
  (fn [base]
    (each key keyz (put base key nil))
    base))

(defn >add
  ```
  Returns a function, that will push `value` into the array base.
  ```
  [value]
  (fn >add [base] (array/push base value)))

(defn >remove
  ```
  Returns a function, that will remove value from the array base at `index`.
  ```
  [index]
  (fn >remove [base]
    (array/remove base index)))

(defn >find-remove
  ```
  Returns a function, that will remove `value` from the array base.
  ```
  [value]
  (fn >remove-val [base]
    (array/remove base (find-index (?eq value) base))))

(defn >find-from-start
  ```
  Returns a function, that finds first member of indexed base 
  for which `pred` is truthy, starting from the start.
  ```
  [pred]
  (fn >find-from-start [base]
    (var i 0)
    (var res nil)
    (while (< i (length base))
      (def item (base i))
      (when (pred item) (set res item) (break))
      (++ i))
    res))

(defn >find-from-end
  ```
  Returns a function, that finds first member of base 
  for which `pred` is truthy starting from the end.
  ```
  [pred]
  (fn >find-from-end [base]
    (var i (dec (length base)))
    (var res nil)
    (while (>= i 0)
      (def item (base i))
      (when (pred item) (set res item) (break))
      (-- i))
    res))

(defn >from-start
  ```
  Returns `i`-th member of the indexed base counted from 
  the start of the base.
  ```
  [i]
  (fn >from-start [base] (in base i)))

(defn >from-end
  ```
  Returns `i`-th member of the indexed base counted from 
  the end of the base.
  ```
  [i]
  (fn >from-end [base]
    (def ni (- (length base) i 1))
    (if-not (neg? ni) (in base ni))))

(defn >partition-by
  "Returns a function, that partitions base by `fn`"
  [fn]
  (fn >paritition-by [base] (partition-by fn base)))

(defn >group-by
  "Returns a function, that groups base by `fn`"
  [fn]
  (fn >group-by [base] (group-by fn base)))

(defn >sort-by
  "Returns a function, that sorts base by `fn`"
  [fn]
  (fn >sort-by [base] (sort-by fn base)))

(defn >if
  ```
  Creates function which calls the `pred` with the base.
  If the result is truthy it returns the `tfnval` call on base.
  If the result is falsey it returns the `ffnval` call on base. 
  `ffnval` detaults to `identity`!
  ```
  [pred tfnval &opt ffnval]
  (default ffnval identity)
  (fn >if [base]
    (if (pred base)
      (tfnval base)
      (ffnval base))))

(defn >base
  "Returns a function, that sets `ds` as the new base."
  [ds]
  (fn >base [_] ds))

(def <-> "Alias to >base" >base)

(defn >assert
  ```
  Returns a function, that asserts `pred` on the base and errors
  with `msg` if it fails.
  ```
  [pred &opt msg]
  (fn >assert [base] (assert (pred base) msg)))

(defn >map-keys
  "Returns a function, that maps all keys in the base with `mapfn`"
  [mapfn]
  (fn >map-keys [base] (map-keys mapfn base)))

(defn >map-vals
  "Returns a function, that maps all values in the base with `mapfn`"
  [mapfn]
  (fn >map-vals [base] (map-vals mapfn base)))

(defn >zipcoll
  "Returns a function, that zipcolls `base` values with `ks`"
  [ks]
  (fn >zipcoll [base] (zipcoll ks base)))

(defn >trace-base
  "Returns a function, that tracev the base"
  [base]
  (tracev base))

(defn >reduce
  "Returns a function, that reduces the base with `fun` and `initial`"
  [fun init]
  (fn :reduce [base] (reduce fun init base)))
