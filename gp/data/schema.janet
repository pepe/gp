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
  - a struct where
    - keys could be one of:
      * function, which is used to extract the items from data to validate
      * any other value, which is used as key to get from data 
    - value is function, which is used to validate
  ```
  ())

(defn fn?
  "Returns `true` if `what` is function or cfunction."
  [what]
  (if-not (function? what) (cfunction? what) true))

(defn validator
  ```
  Creates function which can be used for validating the data.
  It has one argument schema. See `(doc schema)`
  Created function returns the data structure unchanged when it is valid or
  false if it is invalid.
  ```
  [& schema]
  (if (empty? schema)
    (fn truth [_] true)
    (fn validator [data]
      (var ok true)
      (loop [directive :in schema :while ok]
        (set ok
             (match
               (protect
                 (cond
                   (fn? directive) (directive data)
                   (dictionary? directive)
                   (all truthy?
                        (seq [pred :pairs directive]
                          (match pred
                            [(fun (fn? fun)) (afun (fn? afun))]
                            (let [res (fun data)] (afun res))
                            [key (fun (fn? fun))]
                            (fun (get data key)))))))
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
               (cond
                 (fn? directive) (if (directive data) () [data directive])
                 (dictionary? directive)
                 (let [res @{}]
                   (loop [pred :pairs directive]
                     (match pred
                       [(fun (fn? fun)) (afun (fn? afun))]
                       (if-not (fun (afun data)) (put res afun fun))
                       [key (fun (fn? fun))]
                       (if-not (fun (get data key)) (put res key fun))))
                   (freeze res))))
             [true r] r
             [false e] [directive [:error e]]))))))

(def !!! `Alias for analyst` analyst)

# Predicates
(defn present?
  ```
  Returns `true` if `value` is not falsey and is not empty.
  ```
  [value]
  (truthy? (and value (lengthable? value) (not (empty? value)))))

(def epoch? "Alias for number?" number?)

(defn present-string?
  ```
  Returns `true` if value is `present?` and is `string`
  ```
  [value]
  (and (string? value) (present? value)))

(defn string-number?
  ```
  Returns `true` if `value` is `present?` string and
  can be parsed to number
  ```
  [value]
  (and (present-string? value) (not (nil? (scan-number value)))))

# Higher order functions factories
(defn- make-name
  [& parts]
  (symbol (string/join (map describe parts) "-")))

(defn ?one-of
  ```
  Returns a function, that returns `value` if its argument `value`
  is one of `values`.
  ```
  [& values]
  (fn ?one-of [value] (find |(= value $) [;values])))

(defmacro ?gt
  ```
  Returns a function, that checks if the arument `i` is greater
  than `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'gt what) [,i] (,> ,i ,what))))

(defmacro ?gte
  ```
  Returns a function, that checks if the arument i` is greater
  than or equal to `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'gte what) [,i] (,>= ,i ,what))))

(defmacro ?lt
  ```
  Returns a function, that checks if the arument `i` is less
  than `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'lt what) [,i] (,< ,i ,what))))

(defmacro ?lte
  ```
  Returns a function, that checks if the arument `i` is less
  than or equal to `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'lte what) [,i] (,<= ,i ,what))))

(defmacro ?eq
  ```
  Returns a function, that checks if the argument `i` is equal
  to `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'eq what) [,i] (,= ,what ,i))))

(defmacro ?neq
  ```
  Returns a function, that checks if the argument `i` is not equal
  to `what`.
  ```
  [what]
  (with-syms [i] ~(fn ,(make-name 'eq what) [,i] (,not (,= ,what ,i)))))

(defmacro ?deep-eq
  ```
  Returns a function, that checks if the argument `i` is deep equal
  to `what`.
  ```
  [what]
  (with-syms [i]
    ~(fn ,(make-name 'deep-eq what) [,i] (,deep= ,what ,i))))

(defmacro ?matches
  ```
  Returns a function, that matches its arguments
  against the cases, same as if you used core match.
  ```
  [& cases]
  (with-syms [i] ~(fn ?matches [,i] (match ,i ,;cases))))

(defn ?matches-peg
  ```
  Returns a function, that matches its arguments
  against the peg `pg`, and returns the matched.
  ```
  [pg]
  (fn matches-peg? [i] (peg/match pg i)))

(defmacro ?has-key
  ```
  Returns a function, that when called with the dictionary
  returns `true`, if the dictionary has `key`
  ```
  [key]
  (with-syms [i] ~(fn ,(make-name 'has-key key) [,i] (,not= nil (get ,i ,key)))))

(defmacro ?lacks-key
  ```
  Returns a function, that when called with the dictionary
  returns `true`, if the dictionary lacks `key`
  ```
  [key]
  (with-syms [i]
    ~(fn ,(make-name 'lacks-key key) [,i] (,= nil (get ,i ,key)))))

(defmacro ?has-keys
  ```
  Returns a function, that when called with the dictionary
  returns `true`, if the dictionary argumen has all `keyz`.
  ```
  [& keyz]
  (def kfns (map (fn [k] (fn [i] (not= nil (get i k)))) keyz))
  (with-syms [dictionary]
    ~(fn ,(make-name 'has-keys ;keyz) [,dictionary] (all |($ ,dictionary) ,kfns))))

(defmacro ?lacks-keys
  ```
  Returns a function, that returns `true`, if the dictionary argument
  lacks some `keyz`.
  ```
  [& keyz]
  (def name (symbol 'lacks-keys- (string/join keyz "-")))
  (def kfns (map (fn [k] (fn [i] (= nil (get i k)))) keyz))
  (with-syms [dictionary]
    ~(fn ,(make-name 'lacks-keys ;keyz) [,dictionary] (some |($ ,dictionary) ,kfns))))

(defmacro ?num-in-range
  ```
  Returns a function, that checks if the argument is in
  range specified by `boundaries` not inclusive.
  One boundary is used as high and low is set to zero.
  ```
  [& boundaries]
  (def bl (length boundaries))
  (assert (< 0 bl 3) "there must be one or two boundaries")
  (def i (gensym))
  (def name (make-name 'num-in-range ;boundaries))
  (case bl
    1 ~(fn ,name [,i] (< ,i ,(first boundaries)))
    2 ~(fn ,name [,i] (< ,(first boundaries) ,i ,(last boundaries)))))

(defmacro ?long
  "Returns a function, that checks if its argument has the length l"
  [l]
  (with-syms [i]
    ~(fn ,(make-name 'long l) [,i] (= (length ,i) ,l))))

(defn ?prefix
  "Returns a function, that checks if `item` has prefix `pfx`."
  [pfx]
  (fn prefix [i] (string/has-prefix? pfx i)))

(defmacro ?suffix
  "Returns a function, that checks if `item` has suffix `pfx`."
  [sfx]
  (with-syms [i]
    ~(fn ,(make-name 'suffix sfx) [,i] (string/has-suffix? ,sfx ,i))))

(defn ?find
  "Returns a function, that checks if `item` contains `part`."
  [& parts]
  (if (one? (length parts))
    (fn [item] (string/find (parts 0) item))
    (fn name [item]
      (var start 0)
      (loop [part :in [;parts]]
        (if (set start (string/find part item start))
          (+= start (length part))
          (break)))
      start)))

# Selectors
(defmacro from-to
  "Returns a function, that slice its argument `from` `to`"
  [from to]
  (def fn-name (make-name 'from-to from to))
  (with-syms [xs xsl]
    ~(fn ,fn-name [,xs]
       (def ,xsl (length ,xs))
       (if (or (> ,from ,xsl)
               (> (math/abs ,to) ,xsl))
         []
         (slice ,xs ,from ,to)))))

(def rest
  "Selector that returns its argument without the first member"
  (from-to 1 -1))

(def butlast
  "Selector that returns its argument without the last member"
  (from-to 0 -2))

(defmacro def?!
  ```
  Defines both namedvalidator and analyst for the `schema`, named `name?` 
  and `name!`.
  ```
  [name & schema]
  (def validator-name (symbol name "?"))
  (def analyst-name (symbol name "!"))
  (with-syms [item? item!]
    ~(upscope
       (def ,validator-name ,(string name " validator")
         (fn ,validator-name [,item?] ((,??? ,;schema) ,item?)))
       (def ,analyst-name ,(string name " analyst")
         (fn ,analyst-name [,item!] ((,!!! ,;schema) ,item!))))))

(defmacro assert?!
  "Defines assert with message of analyst"
  [schema entity]
  ~(assert (,(symbol schema "?") ,entity) (string/format "%Q" (,(symbol schema "!") ,entity))))

(defmacro assert-not?!
  "Defines assert with message of analyst"
  [schema entity]
  ~(assert (not (,(symbol schema "?") ,entity)) (string/format "%Q" (,(symbol schema "!") ,entity))))

(def email-grammar
  "Grammar to check email"
  (peg/compile
    '{:special (set "!#$%&'*+/=?^_{|}~-")
      :chars (+ :a :d :special)
      :name (* (some :chars) (any (* "." (some :chars))))
      :domain (* (at-least 1 :w) (? (* "-" (some :w) (at-least 1 :w))) "." (at-least 2 :w))
      :main (* :name "@" :domain)}))

(def?! email
  present-string?
  (?matches-peg email-grammar))

(defmacro ?optional
  "Constructs function that check if all `predis` are truthy, or is nil."
  [& preds]
  (with-syms [x]
    ~(fn [,x] (or (= nil ,x) (all |($ ,x) [,;preds])))))
    
(defmacro ?optional-any
  ```
  Checks value is nil OR at least one predicate passes.
  With zero predicates, only nil passes.
  ```
  [& preds]
  (with-syms [x]
    ~(fn [,x]
       (or (= nil ,x)
           (some |($ ,x) [,;preds])))))
