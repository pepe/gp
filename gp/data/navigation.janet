(use spork/misc)

# Eleanor navigation works by the digesting points of the
# path and resetting the current base. Current base is initialy
# the datastructure provided to the function returned by the traverse.
# Every point on path then moves the base through the stucture,
# similarly to how core get-in works.
# The function then returns the latest base as its result. But.
# When you use functions with arity of two as points, they receive 
# the collected array, which can be mutated. If the collected array 
# is not empty at the end of the navigation, base is put at first place 
# in it, and it is returned altogether.

(defn traverse
  ```
  Function that takes a path, which is variadic number
  of points. Point could be function of arrity one which
  is called with current `base`, and its return value is set
  as new base. Or function with arity of two which receives
  `collected` array as second argument. You can mutate collected
  array in the function (see `points/collect`). Its return value
  is again set as the new base. For anything else value
  is used as a key.

  Returns function with arity of one. Its argument should be
  the datastructure on which it navigates.
  ```
  [& path]
  (fn traverse [ds]
    (setdyn :start (os/clock))
    (var base ds)
    (var collected @[])
    (loop [p :in path]
      (match
        (protect
          (case (and (function? p) (disasm p :arity))
            1 (p base)
            2 (p base collected)
            (get base p)))
        [true (nb (not (= nb base)))] (set base nb)
        [false e] (error (string "Point " (describe p) " errored with: " e))))
    (if-not (empty? collected)
      (array/insert collected 0 base)
      base)))

(def => "traverse alias" traverse)

# Points are basic building blocks of the path
# for traverse. Selection here is not complete,
# and can be used as study material.
# Points must be functions, and can return function.
# If the function has arity of two, it will receive
# not only the base, but also collected array, which
# is mutable.

(defn all-by
  ```
  Returns function that maps function `fun` on
  all members of the base.
  ```
  [fun]
  (fn all-by [base]
    (map fun base)))

(def >fn `all-by alias` all-by)

(defn in-all
  ```
  Returns function that maps value under `key` from
  all members of the base.
  ```
  [key]
  (fn in-all [base]
    (map (fn [i] (in i key)) base)))

(def >: `in-all alias` in-all)

(defn filter-by
  ```
  Returns function that filters all members of the base
  by the function `fun`.
  ```
  [fun]
  (fn filter-by [base]
    (filter fun base)))

(def >Y `filter-by alias` filter-by)

(defn check
  ```
  Returns function that checks if `which` members
  of the base conforms to `what` predicate.
  ```
  [which what]
  (fn check [base]
    (which what base)))

(def >?? `check alias` check)

(defn view
  ```
  Returns function that maps `base` and `collected`
  with the function `fun` and returns array for all
  members as new base.
  ```
  [fun]
  (fn view [base collected]
    (map |(fun $ collected) base)))

(def <o> `view alias` view)

(defn limit
  ```
  Returns a function, that limits the number of indexed
  base to `l` members. It retains the base type if possible.
  ```
  [l]
  (fn limit [base]
    (def slfn (case (type base)
                :array array/slice
                :buffer buffer/slice
                :symbol symbol/slice
                :keyword keyword/slice
                slice))
    (if (> l (length base)) base (slfn base 0 l))))

(def >n "Alias for limi" limit)

(defn collect
  ```
  Returns function that collects result of the `fun`
  call on `base`. `fun` is optional, if falsy whole 
  base is collected.
  ```
  [&opt fun]
  (fn collect [base collected]
    (array/push collected (if fun (fun base) base))
    base))

(def <- `collect alias` collect)

(defn drop-collected
  ```
  Drops all the collected values.
  ```
  [base collected]
  (array/clear collected)
  base)

(def <x `drop-collected alias` drop-collected)

(defn merged
  ```
  Returns a function that merges all tables in base to optional `tab`,
  which defaults to `@{}`.
  ```
  [&opt tab]
  (default tab @{})
  (fn [base]
    (merge tab ;base)))

(defn into
  "Returns function which merges `tab` into `base`."
  [tab]
  (fn [base] (merge-into base tab)))

(defn select
  ```
  Returns function which selects `keys` from base 
  and returns new table just with them.
  ```
  [& keys]
  (fn select [i] (select-keys i keys)))

(def >:: `select alias` select)

(defn flatvals
  ```
  Flattens the values of each member of the base.
  ```
  [base]
  (def res @[])
  (loop [t :in base] (array/push res ;(values t)))
  res)

(defn change
  "Returns a function, that changes base under the `key` to new `value`."
  [key value]
  (fn change [base] (put base key value)))

(defn fn-change
  ```
  Changes base under the `key` to result of running `fun` on its value.
  ```
  [key fun]
  (case (disasm fun :arity)
    1 (fn fn-change [base] (update base key fun))
    2 (fn fn-change [base collected] (update base key fun collected))))

(defn add
  ```
  Returns function that will push `value` into the array base.
  ```
  [value]
  (fn add [base] (array/push base value)))

(defn remove
  ```
  Returns function that will remove `value` from the array base.
  ```
  [value]
  (fn remove [base]
    (def index (find-index |(deep= value $) base))
    (array/remove base index)))

(defn trace-base
  ```
  Traces the base
  ```
  [base] (tracev base))

(defn trace-collected
  ```
  Traces the collected.
  ```
  [base collected]
  (tracev collected)
  base)

(defn trace-elapsed
  ```
  Traces thetime from the begining of the path
  ```
  [base]
  (eprintf "Elapsed: %fms" (* 1000 (- (os/clock) (dyn :start))))
  base)

(defn drop-elapsed
  ```
  Sets the start to now
  ```
  [base]
  (setdyn :start (os/clock))
  base)

(defn find-from-start
  ```
  Find first member of indexed `base` for which `pred` is truthy,
  starting from the start.
  ```
  [pred]
  (fn find-from-start [base]
    (var i 0)
    (var res nil)
    (while (< i (length base))
      (def item (base i))
      (when (pred item) (set res item) (break))
      (++ i))
    res))

(defn find-from-end
  ```
  Find first member of `base` for which `pred` is truthy
  starting from the end.
  ```
  [pred]
  (fn find-from-end [base]
    (var i (dec (length base)))
    (var res nil)
    (while (>= i 0)
      (def item (base i))
      (when (pred item) (set res item) (break))
      (-- i))
    res))

(defn from-start
  ```
  Returns i-th member of the indexed `base` counted from 
  the start of the base.
  ```
  [i]
  (fn from-start [base]
    (in base i)))

(defn from-end
  ```
  Returns i-th member of the indexed `base` counted from 
  the end of the base.
  ```
  [i]
  (fn from-end [base]
    (def ni (- (length base) i 1))
    (if-not (neg? ni) (in base ni))))

(defn partitioned-by
  "Returns function that partitions base on `fn`"
  [fn]
  (fn parititioned-by [base] (partition-by fn base)))

(defn grouped-by
  "Returns function that groups base on `fn`"
  [fn]
  (fn parititioned-by [base] (group-by fn base)))

(defn const
  "Collect given `cnst`"
  [cnst]
  (fn const [b c] (array/push c cnst) b))

(defn on
  ```
  Conditional navigation and transformation on predicate.

  * `pred` is a functions which on arity one receives just base, 
    on arity two base and collected.
  * `tfnval` if it is a function it will receive base (and collected)
    and result of the call is set as the new base. Otherwise its value 
    is set as the new base.
  * optional `ffnval` falsey branch of the conditional, same as `tfnval`
    but for the negative result of the `pred`.

  If predicates returns false, base is not changed.
  ```
  [pred tfnval &opt ffnval]
  (case (disasm pred :arity)
    1 (fn on [base]
        (if (pred base)
          (if (function? tfnval) (tfnval base) tfnval)
          (if ffnval
            (if (function? ffnval)
              (ffnval base) ffnval)
            base)))
    2 (fn on [base collected]
        (if (pred base collected)
          (if (function? tfnval) (tfnval base collected) tfnval)
          (if ffnval
            (if (function? ffnval)
              (ffnval base collected) ffnval)
            base)))))

(defn collected->base
  "Sets collected as the new base"
  [_ c] (array/slice c))

(def <->
  "Alias to collected->base"
  collected->base)

(defn asserted
  "Asserts `pred` on the `base` and errors with `msg` if it fails."
  [pred &opt msg]
  (fn asserted [base] (assert (pred base) msg)))

(defn mapkeys
  "Maps all keys in table base with `mapfn`"
  [mapfn]
  (fn mapkeys [base] (map-keys mapfn base)))

(defn mapvals
  "Maps all vals in table base with `mapfn`"
  [mapfn]
  (fn mapvals [base] (map-vals mapfn base)))

(defmacro base-collected-seq
  "Constructs function with arity two with `seq` inside, that steps through 
  base and collected in one run and assigns items to `basei` and `collectedi`
  and `body`."
  [basei collectedi & body]
  (with-syms [b c]
    ~(fn base-collected-seq [,b [,c]]
       (seq [,basei :in ,b ,collectedi :in ,c] ,;body))))
