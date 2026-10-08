(use spork/test spork/misc)
(use gp/data/schema)
(import gp/data/navigation :as nav)
(start-suite "Schema documentation")
(assert-docs "gp/data/schema")
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

(assert (= {} ((validator struct? {keys (nav/>check all keyword?)}) {}))
        "call keys validator with wrong data")

(assert ((validator struct? {keys (nav/>check all keyword?)}) {:a "a"})
        "call keys validator with right data")

(assert (= {} ((validator struct? {values (nav/>check all keyword?)}) {}))
        "call values validator with wrong data")

(assert ((validator struct? {values (nav/>check all string?)}) {:a "a"})
        "call values validator with right data")

(assert (= {} ((validator struct? {keys (nav/>check all keyword?)
                                   values (nav/>check all string)}) {}))
        "call key and value validator with wrong data")

(assert ((validator struct? {keys (nav/>check all keyword?)
                             values (nav/>check all string?)}) {:a "a"})
        "call key and value validator with right data")

(assert ((validator array? {values (nav/>check all number?)}) @[1 2 3])
        "validate array of numbers")

(assert ((validator struct? {:a string?}) {:a "hoho"})
        "validator with key predicate")

(assert ((validator struct? {:a string? :b number?})
          {:a "hoho" :b 1})
        "validator with keys predicates")

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
                               struct? {values (nav/>check all string?)})}) :b number?})
          {:a @{:c {:d "HOHO" :e "HOHOO"}} :b 1})
        "validate with more nested predicates")

(assert (??? {:a @{:c {:d "HOHO" :e "HOHOO"}} :b 1}
             struct? {:a (???
                           table?
                           {:c (???
                                 struct? {values string?})}) :b number?})
        "alias with more nested predicates")

(defn in-right? [age]
  (<= 45 age 50))

(assert (function? (analyst table?))
        "analyst is a function")

(assert ((validator tuple? empty?) ((analyst table?) @{}))
        "analyst of valid is empty tuple")

(assert ((validator tuple? present?) ((analyst table?) {}))
        "analyst of invalid is tuple with blocker is nonempty tuple")

(assert ((validator
           tuple? {0 (??? tuple? {0 (?eq {}) 1 function?})}) ((analyst table?) {}))
        "analyst of invalid is tuple with blocker tuple with pair of predicate and failing data")

(assert ((validator
           tuple? {0 empty?
                   1 (??? struct? {:name function?})})
          ((analyst table? {:name string?}) @{:name 1}))
        "analyst of invalid is array with blocker validated")

(def keywords? (nav/>check all keyword?))
(assert (deep= [() {keys keywords?}]
               ((analyst struct? {keys keywords?}) {"a" 1}))
        "analyst extracts with a function key before it checks")
(assert (deep= [{first string?}] ((analyst {first string?}) [1]))
        "analyst reports a function key with its predicate")
(assert (deep= [] ((analyst {first string?}) ["a"]))
        "analyst of a valid function key is empty")

(assert-no-error "catch validate errors" ((??? nil? empty?) nil))

(assert ((???
           {0 (?eq :error)
            1 (?eq "expected iterable type, got nil")})
          (gett ((!!! nil? empty?) nil) 1 1))
        "catch analyst errors")

(assert ((validator @{:hello string?}) @{:hello "hoho"})
        "table spec")

(end-suite)

(start-suite "Predicates and Selectors")

(assert ((validator array? {first string?}) @["1"]) "first pred")

(assert (deep= ((from-to 1 -1) @["1" 1 2]) [1 2]) "from-to pred")
(assert (deep= ((from-to 0 -2) @[]) []) "from-to oob")
(assert (deep= ((from-to 1 0) @[]) []) "from-to oob")
(assert ((validator array? {(from-to 1 -1) (nav/>check all number?)}) @["1" 1 2]) "from-to")

(assert ((validator array? {rest (nav/>check all number?)}) @["1" 1 2]) "rest")

(assert ((validator array? {butlast (nav/>check all number?)}) @[1 2 "1"]) "butlast")

(assert ((validator {:some nil?}) {}) "nil?")

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

(assert (function? (?one-of "active" "completed" "canceled"))
        "one-of function")

(assert ((?one-of "active" "completed" "canceled") "active")
        "?one-of with value")

(assert (not ((?one-of "completed" "canceled") "active"))
        "not ?one-of with value")

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

(assert ((?gt 1) 2)
        "gt function call")

(assert ((?lt 2) 1)
        "?lt function call")

(assert ((?gte 1) 1)
        "gt function call")

(assert ((?gte 2) 2)
        "gt function call")

(assert ((?lte 2) 1)
        "?lt function call")

(assert ((?lte 1) 1)
        "?lt function call")

(assert ((?eq :a) :a)
        "eq function call")

(assert ((?deep-eq @"a") @"a")
        "?deep-eq function call")

(assert (= ((?matches
              (s (bytes? s)) (string "We need " s)
              (i (number? i)) (inc i))
             "peace")
           "We need peace")
        "?matches function call")

(assert (= ((?matches
              (s (bytes? s)) (string "We need " s)
              (i (number? i)) (inc i))
             41)
           42)
        "?matches function call")

(assert (deep= ((?matches-peg ~(* "a " '(to " ") (to :d) (number (to -1))))
                 "a peace is a number 1")
               @["peace" 1])
        "?matches-peg function")

(assert ((?has-key :state) {:state true})
        "?has-key")

(assert-not ((?has-key :state) {:stute true})
            "?has-key")

(assert ((?has-keys :state :start) {:state true :start true})
        "has-keys?")

(assert-not ((?has-keys :state :start) {:state nil :start true})
            "not ?has-keys")

(assert ((?lacks-key :state) {:stute true})
        "lacks-key?")

(assert-not ((?lacks-key :state) {:state true})
            "not lacks-key?")

(assert ((?lacks-keys :state :start) {:state nil :start true})
        "lacks-keys?")

(assert-not ((?lacks-keys :state :start) {:state true :start true})
            "not lacks-keys?")

(assert ((?num-in-range 10) 8)
        "num in range hi boundary")

(assert-not ((?num-in-range 10) 18)
            "not num in range hi boundary")

(assert ((?num-in-range 7 10) 8)
        "num in range boundaries")

(assert-not ((?num-in-range 7 10) 18)
            "not num in range boundaries")

(assert ((?long 4) "pepe") "?long")

(assert ((?prefix "pe") "pepa"))
(assert ((?suffix "pa") "pepa"))
(assert ((?find "ep") "pepa"))
(assert ((?find "pe" "pa") "pepa"))
(assert ((?find "pe" "pa") "peepa"))
(assert (not ((?find "pr" "pe") "pepa")))
(assert (epoch? (os/time)))
(assert ((?optional) nil) "preds can be empty")
(assert ((?optional number?) nil) "can be nil")
(assert ((?optional number?) 3) "can be number")
(assert-not ((?optional number?) "3") "must be number")
(assert ((?optional number? pos?) 3) "can have more predicates")
(assert-not ((?optional number? neg?) 3) "all predicates must be truthy")

(assert ((?optional-any number?) nil) "can be nil")
(assert ((?optional-any number?) 3) "can be number")
(assert-not ((?optional-any number?) "3") "must be number")
(assert ((?optional-any number? string?) "3") "can be number or string")
(assert ((?optional-any) nil) "with zero preds only nil passes")
(assert-not ((?optional-any) 0) "zero preds: non-nil should fail")
(assert-not ((?optional-any number? string?) :kw) "neither number nor string fails")

(end-suite)

(start-suite "Helpers")
(def?! odd-arr
  array? (nav/>check all odd?))
(assert?! odd-arr @[1 3 5])
(assert-not?! odd-arr @[1 2 3 5])
(end-suite)
(start-suite "def?! metadata")
(def?! plain-kw keyword?)
(assert (deep= [["hoho" keyword?]] (plain-kw! "hoho"))
        "without metadata the analyst reports the value")
(assert (deep= ((!!! keyword?) "hoho") (plain-kw! "hoho"))
        "without metadata the analyst is the plain analyst")
(assert (nil? ((dyn 'plain-kw!) :validation))
        "without metadata the analyst has no format")

(def?! a-kw "%q is not keyword" keyword?)
(assert (= "%q is not keyword" ((dyn 'a-kw!) :validation))
        "a leading string is the analyst's :validation")
(assert (nil? ((dyn 'a-kw?) :validation)) "the validator gets no metadata")
(assert (deep= [["\"hoho\" is not keyword" keyword?]] (a-kw! "hoho"))
        "the analyst formats the failing value")
(assert (deep= [] (a-kw! :hoho)) "the analyst of valid data is empty")
(assert (= :hoho (a-kw? :hoho)) "a leading string is not schema")
(assert-not (a-kw? "hoho") "a leading string leaves the validator alone")

(def?! named "%q is not a name" struct? {:name string?})
(assert (deep= [() {:name ["1 is not a name" string?]}] (named! {:name 1}))
        "the analyst formats failing values in a struct")
(def?! first-named "%q is not a name" {first string?})
(assert (deep= [{first ["1 is not a name" string?]}] (first-named! [1]))
        "the analyst formats failing values under a function key")

(setdyn :schema-test/string "%q is not a port")
(def?! env-port :schema-test/string int?)
(assert (= "%q is not a port" ((dyn 'env-port!) :validation))
        "a keyword can resolve to a string")
(assert (deep= [["\"80\" is not a port" int?]] (env-port! "80"))
        "a string from a keyword formats the failing value")
(assert (= 80 (env-port? 80)) "a leading keyword is not schema")

(setdyn :schema-test/struct {:validation "%q is not an api port" :posture :api})
(def?! api-port :schema-test/struct int?)
(assert (= :api ((dyn 'api-port!) :posture))
        "a keyword can resolve to a struct")
(assert (deep= [["nil is not an api port" int?]] (api-port! nil))
        "a struct's :validation formats the failing value")

(def provided @[])
(defn provider [kw schema]
  (array/push provided [kw schema])
  (case kw
    :schema-test/validation (string "%q fails " (length schema) " forms")
    :schema-test/api {:api schema}))
(setdyn :schema-test/validation provider)
(setdyn :schema-test/api provider)
(def?! valid-port :schema-test/validation int? (?gt 0))
(def?! api-field :schema-test/api {:field string?})
(assert (= "%q fails 2 forms" ((dyn 'valid-port!) :validation))
        "a keyword can resolve to a provider")
(assert (= "0 fails 2 forms" (get-in (valid-port! 0) [1 0]))
        "a provided format formats the failing value")
(assert (deep= {:field 'string?} (first ((dyn 'api-field!) :api)))
        "one provider serves many keywords")
(assert (deep= [{:field string?}] (api-field! {:field 1}))
        "metadata without :validation leaves the analyst plain")
(assert (deep= [:schema-test/validation ['int? '(?gt 0)]] (provided 0))
        "a provider gets the keyword and the unevaluated rest of the schema")
(assert (= :schema-test/api (first (provided 1)))
        "a provider gets the keyword it was found under")
(assert (= 80 (valid-port? 80)) "a provided keyword is not schema")
(assert-not (valid-port? 0) "a provided keyword leaves the schema whole")

(def?! unset-port :schema-test/unset int?)
(assert (nil? ((dyn 'unset-port!) :validation))
        "an unset keyword gives no metadata")
(assert (= 80 (unset-port? 80)) "an unset keyword is not schema")

(defn meta-lints
  "Compiles a `def?!` whose keyword resolves to `source`, returning lints."
  [source]
  (def env (make-env (curenv)))
  (put env :schema-test/meta source)
  (def lints @[])
  (compile '(def?! linted :schema-test/meta int?) env "meta-lints" lints)
  (map |[($ 0) ($ 3)] lints))
(assert (empty? (meta-lints "fine")) "a valid source lints nothing")
(assert (deep= @[[:error ":schema-test/meta provider returned number, expected string or struct"]]
               (meta-lints (fn [& _] 42)))
        "a provider must return a string or struct")
(assert (deep= @[[:error ":schema-test/meta provider returned nil, expected string or struct"]]
               (meta-lints (fn [& _] nil)))
        "a provider must return something")
(assert (deep= @[[:error ":schema-test/meta is table, expected string, struct or function"]]
               (meta-lints @{:validation "mutable"}))
        "a keyword must resolve to a string, struct or function")

(def?! fielded {:field string?})
(assert (fielded? {:field "x"}) "a leading struct is schema")
(assert-not (fielded? {:field 1}) "a leading struct validates")
(assert (nil? ((dyn 'fielded!) :field)) "a leading struct is not metadata")
(end-suite)
(start-suite "email")
(assert (peg/match email-grammar "josef.pospisil@laststar.eu"))
(assert (peg/match email-grammar "josefpospisil@laststar.eu"))
(assert (peg/match email-grammar "josefpospisil@work.laststar.eu"))
(assert (not (peg/match email-grammar "josefpospisil@laststar")))
(assert (peg/match email-grammar "josef^pospisil@work.laststar.eu"))
(assert (peg/match email-grammar "josef^pos#pisil@work.laststar.eu"))
(assert (not (peg/match email-grammar "josef@pospisil@laststar.cz")))
(each address ["x@tu-berlin.de" "x@mail.tu-berlin.de" "x@uni-lj.si"
               "o'neill@student.example" "x@a--b.cz"]
  (assert (email? address) (string "A hyphenated domain is an address: " address)))
(each address ["x@" "x@tu" "a b@c.de" "x@y.cz trailing" "x@-a.cz" "x@a-.cz"
               "x@a.c" "x@a.c2"]
  (assert-not (email? address) (string "Not an address: " address)))
(end-suite)
