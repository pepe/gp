(use spork/test spork/misc)
(use ../gp/data/schema)
(start-suite "Schema documentation")
(assert-docs "../gp/data/schema")
(end-suite)
(start-suite "Validator and Analyst")

(assert (validator []) "validator exists")

(assert (function? (validator [])) "validator function")

(assert (false? ((validator struct?) @{}))
        "call validator with wrong data")

(assert ((validator struct?) {})
        "call validator with right struct")

(assert ((validator number?) 1)
        "call validator with right number")

(assert (= {} ((validator struct? {keys keyword?}) {}))
        "call keys validator with wrong data")

(assert ((validator struct? {keys keyword?}) {:a "a"})
        "call keys validator with right data")

(assert (= {} ((validator struct? {values keyword?}) {}))
        "call values validator with wrong data")

(assert ((validator struct? {values string?}) {:a "a"})
        "call values validator with right data")

(assert (= {} ((validator struct? {keys keyword? values string?}) {}))
        "call key and value validator with wrong data")

(assert ((validator struct? {keys keyword? values string?}) {:a "a"})
        "call key and value validator with right data")

(assert ((validator array? {values number?}) @[1 2 3])
        "validate array of numbers")

(assert ((validator struct? {:a string?}) {:a "hoho"})
        "validator with key predicate")

(assert ((validator struct? {:a string? :b number?})
          {:a "hoho" :b 1})
        "validator with keys predicates")

(assert ((validator
           struct? {:a string? :b number?})
          {:a "hoho" :b 1})
        "validate with keys predicates")

(assert ((validator
           struct? {:a string? :b number?}) {:a "hoho" :b 1})
        "validate with keys predicates")

(assert ((validator array? {values [some nil? number?]}) @[1 2 3 nil])
        "validate with keys some multi predicates")

(assert (false? ((validator array? {values [some nil? number?]}) @[1 2 3 nil "a"]))
        "do not validate with keys some multi predicates")

(assert ((validator array? {values [all number? pos?]}) @[1 2 3])
        "validate with keys all multi predicates")

(assert (false? ((validator array? {:a [all number? pos?]
                                    :b [all string? empty?]}) {:a 1 :b ""}))
        "do not validate with keys all multi predicates")

(assert ((validator struct? {:a [all number? pos?]
                             :b [all string? empty?]}) {:a 1 :b ""})
        "validate with keys all multi predicates")

(assert (false? ((validator array? {values [all number? pos?]}) @[1 2 3 -1]))
        "do not validate with keys all multi predicates")

(assert ((validator
           struct? {:a (validator table? {:c string?}) :b number?}) {:a @{:c "hoho"} :b 1})
        "validate with nested predicates")

(assert (deep=
          ((validator
             struct? {:a (validator table? {:c string?}) :b number?})
            {:a @{:c "hoho"} :b 1})
          {:a @{:c "hoho"} :b 1})
        "validate with nested predicates return value")

(assert ((validator
           struct? {:a (validator
                         table?
                         {:c (validator
                               struct? {values string?})}) :b number?})
          {:a @{:c {:d "HOHO" :e "HOHOO"}} :b 1})
        "validate with more nested predicates")

(assert (??? {:a @{:c {:d "HOHO" :e "HOHOO"}} :b 1}
             struct? {:a (???
                           table?
                           {:c (???
                                 struct? {values string?})}) :b number?})
        "alias with more nested predicates")

(assert ((validator [some string? buffer?]) "HOHO")
        "tuple type some string")

(assert ((validator [some string? buffer?]) @"HOHO")
        "tuple type some buffer")

(assert ((validator [all buffer? present?]) @"HOHO")
        "tuple type all present")

(assert (false? ((validator [all buffer? present?]) @""))
        "tuple type all present")

(assert (false? ((validator [some string? nil?]) 7))
        "wrong type with tuple")

(defn in-right? [age]
  (<= 45 age 50))

(assert ((validator array? {values [all number? in-right?]}) @[45 46 48])
        "validate with keys all multi custom predicates")

(assert ((validator array? {values [some string? in-right?]}) @["young" 46 48])
        "validate with keys some multi custom predicates")

(assert (function? (analyst table?))
        "Anaylyst is a function")

(assert ((validator tuple? empty?) ((analyst table?) @{}))
        "Anaylyst of valid is empty tuple")

(assert ((validator tuple? present?) ((analyst table?) {}))
        "Anaylyst of invalid is tuple with blocker is nonempty tuple")

(assert ((validator
           tuple? {0 (??? tuple? {0 (eq {}) 1 function?})}) ((analyst table?) {}))
        "Anaylyst of invalid is tuple with blocker tuple with pair of predicate and failing data")

(assert ((validator
           tuple? {0 empty?
                   1 (??? struct? {:name function?})})
          ((analyst table? {:name string?}) @{:name 1}))
        "Anaylyst of invalid is array with blocker validated")

(assert ((validator
           tuple? {0 empty?
                   1 (??? struct? {:age tuple?})})
          ((analyst table? {:name string? :age [all number? pos?]})
            @{:name "pepe" :age -1}))
        "Anaylyst of invalid data is array with tuple blocker")

(assert ((validator
           tuple? {0 empty?
                   1 (??? struct? {:name function?
                                   :age tuple?})})
          ((analyst table? {:name present-string? :age [all number? pos?]})
            @{:name "" :age -1}))
        "Anaylyst of invalid data is array with more tuple blockers")

(assert ((validator
           tuple? {0 empty?
                   1 (??? struct? {:name function?
                                   :age tuple?})})
          ((!!! table? {:name present-string? :age [all number? pos?]})
            @{:name "" :age -1}))
        "Alias anaylyst of invalid data is array with more tuple blockers")

(assert (= ((analyst [all buffer? present?]) @"HOHO") '())
        "analyst tuple type all present")

(assert (not= ((analyst [all string? present?]) @"HOHO") '())
        "analyst tuple type all present not string")

(assert ((validator
           tuple? {0 (??? tuple? {0 (deep-eq @"HOHO")})})
          ((analyst [all string? present?]) @"HOHO"))
        "analyst tuple type all present not string")

(assert-no-error "catch validate errors"
                 ((??? nil? empty?) nil))

(assert ((validator
           tuple? {0 [all tuple? empty?]
                   1 (??? tuple? {0 (eq empty?)
                                  1 (???
                                      tuple? {0 (eq :error)
                                              1 (eq "expected iterable type, got nil")})})})
          ((!!! nil? empty?) nil))
        "catch analyst errors")

(assert ((validator @{:hello string?}) @{:hello "hoho"})
        "table spec")

(assert ((validator @{values @[all string?]}) @{:hello "hoho"})
        "array spec")

(assert ((validator array? {first string?}) @["1"]) "first pred")

(assert (deep= ((from-to 1 -1) @["1" 1 2]) [1 2]) "from-to pred")
(assert (deep= ((from-to 0 -2) @[]) []) "from-to oob")
(assert (deep= ((from-to 1 0) @[]) []) "from-to oob")
(assert ((validator array? {(from-to 1 -1) number?}) @["1" 1 2]) "from-to")

(assert ((validator array? {rest number?}) @["1" 1 2]) "rest")

(assert ((validator array? {butlast number?}) @[1 2 "1"]) "butlast")

(assert ((validator array? {butlast [some keyword? string? number?]})
          @[1 "3" :a 2 "1"]) "butlast tuple")

(assert ((validator array? {last [some keyword? string? number?]})
          @[1 "3" :a 2 "1"]) "last tuple")

(assert ((validator {:some nil?}) {}) "nil?")

(end-suite)

(start-suite "Predicates and Selectors")

(assert (present? "present")
        "present")

(assert (false? (present? ""))
        "not present empty")

(assert (present? [1])
        "present")

(assert (false? (present? []))
        "not present empty")

(assert (false? (present? nil))
        "not present nil")

(assert (function? (one-of? "active" "completed" "canceled"))
        "one-of function")

(assert ((one-of? "active" "completed" "canceled") "active")
        "one-of? with value")

(assert (not ((one-of? "completed" "canceled") "active"))
        "not one-of? with value")

(assert (present-string? "present")
        "present string")

(assert (false? (present-string? [1]))
        "not present string")

(assert (false? (present-string? nil))
        "not present string")

(assert (string-number? "123")
        "string number")

(assert (false? (string-number? "A123"))
        "not string number")

(assert ((gt 1) 2)
        "gt function call")

(assert ((lt 2) 1)
        "lt function call")

(assert ((gte 1) 1)
        "gt function call")

(assert ((gte 2) 2)
        "gt function call")

(assert ((lte 2) 1)
        "lt function call")

(assert ((lte 1) 1)
        "lt function call")

(assert ((eq :a) :a)
        "eq function call")

(assert ((deep-eq @"a") @"a")
        "deep-eq function call")

(assert (= ((matches?
              (s (bytes? s)) (string "We need " s)
              (i (number? i)) (inc i))
             "peace")
           "We need peace")
        "matches? function call")

(assert (= ((matches?
              (s (bytes? s)) (string "We need " s)
              (i (number? i)) (inc i))
             41)
           42)
        "matches? function call")

(assert (deep= ((matches-peg? ~(* "a " '(to " ") (to :d) (number (to -1))))
                 "a peace is a number 1")
               @["peace" 1])
        "matches-peg? function")

(assert ((has-key? :state) {:state true})
        "has-key?")

(assert-not ((has-key? :state) {:stute true})
            "has-key?")

(assert ((has-keys? :state :start) {:state true :start true})
        "has-key?")

(assert-not ((has-keys? :state :start) {:state nil :start true})
            "not has-key?")

(assert ((lacks-key? :state) {:stute true})
        "lacks-key?")

(assert-not ((lacks-key? :state) {:state true})
            "not lacks-key?")

(assert ((lacks-keys? :state :start) {:state nil :start true})
        "lacks-keys?")

(assert-not ((lacks-keys? :state :start) {:state true :start true})
            "not lacks-keys?")

(assert ((num-in-range 10) 8)
        "num in range hi boundary")

(assert-not ((num-in-range 10) 18)
            "not num in range hi boundary")

(assert ((num-in-range 7 10) 8)
        "num in range boundaries")

(assert-not ((num-in-range 7 10) 18)
            "not num in range boundaries")

(assert ((long? 4) "pepe") "long?")

(define-registry "Test registry" :string-keys {keys present-string?})
(assert ((??? (registry->schema :string-keys)) @{"1" "2"})
        "valid registry")
(assert-not ((??? (registry->schema :string-keys)) @{:1 "2"})
            "invalid registry")
(end-suite)
