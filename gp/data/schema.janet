# Simple module for validating and analysing
# data structures in Janet.
# It has at the moment two main modes of function, which
# coresponds to the two functions in this module:
# - validator
# takes schema and returns function which takes datastructure
# as an argument. If the datastructure conform to the schema
# it is returned unchanged, if not false is returned.
# - analyst
# takes schema and returns function which takes datastructure
# as an argument. If datastructure conforms to the schema
# empty parts of the schema are returned. If not, offending
# parts are returned according to schema with the predicates
# that were not met.

(def schema
  ```
  Schema is variadic argument for module functions, where members
  are predicates for the type of the data:
  - functions (string?, struct? etc.) with which the whole datastructure
    is tested.
  - a tuple of functions, where first is mapping function (all, some etc.)
    and rest are predicates which will be tested on the data.
  - a struct, where keys could be one of:
    * function, which is used to extract the items from data to validate
    * any other value, which is used as key to get from data
  - and values could be one of:
    * function, which is used to validate
    * tuple of functions, where first is mapping function and rest
      are predicates which will be tested on each member of the data
  ```
  ())

(defn validator
  ```
  Creates function which can be used for validating the data.
  It has one argument schema. See `(doc schema)`
  The function returns the data structure unchanged when it is valid or
  false.
  ```
  [& schema]
  (if (empty? schema)
    (fn truth [&] true)
    (fn validato [data]
      (var ok true)
      (loop [directive :in schema :while ok]
        (set ok
             (match
               (protect
                 (cond
                   (function? directive) (directive data)
                   (or (tuple? directive) (array? directive))
                   (let [fun (directive 0)
                         preds (tuple/slice directive 1 -1)]
                     (fun |($ data) preds))
                   (dictionary? directive)
                   (all truthy?
                        (seq [pred :pairs directive]
                          (match pred
                            [(fun (function? fun)) (afun (function? afun))]
                            (let [res (fun data)]
                              (if (indexed? res)
                                (all afun res)
                                (afun res)))
                            [key (fun (function? fun))]
                            (fun (get data key))
                            [head (idx (indexed? idx))]
                            (let [v (if (function? head)
                                      (head data)
                                      [(get data head)])
                                  fun (idx 0)
                                  preds (slice idx 1 -1)]
                              (if (indexed? v)
                                (all (fn [i] (fun |($ i) preds)) v)
                                (fun |($ v) preds))))))))
               [true res] res
               [false _] false)))
      (if ok data false))))

(def ??? `Alias for validator` validator)

(defn analyst
  ```
  Creates function which can be used for analysing the data structure.
  It has one argument schema. See `(doc schema)`
  The function returns the empty tuple when it is valid
  or data structure mimicking the schema, with nonconforming members
  and predicate, that failed.
  ```
  [& schema]
  (fn analyst [data]
    (if ((validator ;schema) data)
      []
      (tuple
        ;(seq [directive :in schema]
           (match
             (protect
               (case (type directive)
                 :function (if (directive data) () [data directive])
                 :tuple
                 (let [fun (directive 0)
                       preds (tuple/slice directive 1 -1)]
                   (if (fun |($ data) preds) [] [data directive]))
                 :struct
                 (let [res @{}]
                   (loop [pred :pairs directive]
                     (match pred
                       [(afun (function? fun)) (fun (function? afun))]
                       (if-not (all fun (afun data)) (put res afun fun))
                       [key (fun (function? fun))]
                       (if-not (fun (get data key)) (put res key fun))
                       [head (tup (tuple? tup))]
                       (let [v (if (function? head)
                                 (head data)
                                 [(get data head)])
                             fun (tup 0)
                             preds (tuple/slice tup 1 -1)]
                         (if-not (all (fn [i] (fun |($ i) preds)) v)
                           (put res head tup)))))
                   (freeze res))))
             [true r] r
             [false e] [directive [:error e]]))))))

(def !!! `Alias for analyst` analyst)

###
### Predicates for appraising.
###

(defn present?
  ```
  Returns true if `value` is not falsey and is not empty.
  ```
  [value]
  (truthy? (and value (not (empty? value)))))

(defn one-of?
  ```
  Returns function that check if its argument `value`
  is one `values`.
  ```
  [& values]
  (fn one-of? [value]
    (not (nil? (some |(= value $) values)))))

(defn present-string?
  ```
  Returns true if value is `present?` and is `string`
  ```
  [value] (and (present? value) (string? value)))

(defn string-number?
  ```
  Returns true if `value` is `present?` string and
  can be parsed to number
  ```
  [value]
  (and (present-string? value) (not (nil? (scan-number value)))))

(defn gt
  ```
  Returns function that checks if the arument `i` is greater
  than `what`.
  ```
  [what]
  (fn gt [i] (> i what)))

(defn gte
  ```
  Returns function that checks if the arument `i` is greater
  than or equal to `what`.
  ```
  [what]
  (fn gt [i] (>= i what)))

(defn lt
  ```
  Returns function that checks if the arument `i` is less
  than `what`.
  ```
  [what]
  (fn lt [i] (< i what)))

(defn lte
  ```
  Returns function that checks if the arument `i` is less
  than or equal to `what`.
  ```
  [what]
  (fn lt [i] (<= i what)))

(defn eq
  ```
  Returns function that checks if the argument `i` is equal
  to `what`.
  ```
  [what]
  (fn eq [i] (= what i)))

(defn deep-eq
  ```
  Returns function that checks if the argument `i` is deep equal
  to `what`.
  ```
  [what]
  (fn eq [i] (deep= what i)))

(defmacro matches?
  ```
  Returns function that matches its arguments
  against the cases, same as if you used core match.
  ```
  [& cases]
  (with-syms [i]
    ~(fn matches? [,i]
       (match ,i ,;cases))))

(defn matches-peg?
  ```
  Returns function that matches its arguments
  against the peg `pg`, and returns the matched.
  ```
  [pg]
  (fn matches-peg? [i]
    (peg/match pg i)))

(defn has-key?
  ```
  Returns function, which when called with the dictionary
  returns true, if the dictionary has `key`
  ```
  [key]
  (fn has-key? [i] (not= nil (i key))))

(defn lacks-key?
  ```
  Returns function, which when called with the dictionary
  returns true, if the dictionary lacks `key`
  ```
  [key]
  (fn lacks-key? [i] (= nil (i key))))

(defn has-keys?
  ```
  Returns function, which when called with the dictionary
  returns true, if the dictionary has all `keyz`
  ```
  [& keyz]
  (def kfns (map |(has-key? $) keyz))
  (fn has-keys? [i] (all |($ i) kfns)))

(defn lacks-keys?
  ```
  Returns function, which when called with the dictionary
  returns true, if the dictionary lacks all `keyz`
  ```
  [& keyz]
  (def kfns (map |(lacks-key? $) keyz))
  (fn lacks-keys? [i] (some |($ i) kfns)))

(defn num-in-range
  ```
  Returns function that checks if the argument is in
  range specified by `boundaries` not inclusive.
  One boundary is used high one with low set to zero.
  ```
  [& boundaries]
  (case (length boundaries)
    1 (fn [i] (< i (first boundaries)))
    2 (fn [i] (< (first boundaries) i (last boundaries)))))

(defn long?
  "Returns function that checks if its argument has the length l"
  [l]
  (fn long? [i] (= (length i) l)))

###
### Selectors for appraising
###

(defn from-to
  "Returns function that slice its argument `from` `to`"
  [from to]
  (fn [xs] (slice xs from to)))

(def rest
  "Selector that returns its argument without the first member"
  (from-to 1 -1))

(def butlast
  "Selector that returns its argument without the last member"
  (from-to 0 -2))
