(use spork/test spork/misc)
(use gp/data/navigation)
(use gp/data/schema)
(use gp/data/magic)
(start-suite "Magic documentation")
(assert-docs "gp/data/magic")
(end-suite)

(start-suite "wand")
(def user @{:user {:name "pepe"}})
(def ouser @{:user {:name "opepe"}})
(assert wand "Wand macro")
(assert (= "pepe" ((wand :user :name) user)) "wand literals")
(assert (= "pepe" ((=<> :user :name) user)) "=<> literals")
(assert (= "PEPE" ((wand :user :name string/ascii-upper) user)) "wand fn")
(assert (= "PEPE" ((=<> :user :name string/ascii-upper) user)) "=<> fn")
(assert (= "PEPE" ((wand :user {:name string?} :name string/ascii-upper) user)) "wand gate succ")
(assert (= "PEPE" ((=<> :user {:name string?} :name string/ascii-upper) user)) "=<> gate succ")
(assert (nil? ((wand :user {:name number?} :name string/ascii-upper) user)) "wand gate fail")
(assert (nil? ((=<> :user {:name number?} :name string/ascii-upper) user)) "=<> gate fail")
(assert (= {:name "pepe"} ((wand :user {:name string?}) user)) "wand gate succ whole")
(assert (= {:name "pepe"} ((=<> :user {:name string?}) user)) "=<> gate succ whole")
(assert (nil? ((wand :user {:name string?} (<> escape) :name string/ascii-upper) user)) "wand escape")
(assert (nil? ((=<> :user {:name string?} (<> escape) :name string/ascii-upper) user)) "=<> escape")
(assert (= "PEPE" ((wand :user {:name string?} (<> maybe) :name string/ascii-upper)
                    user)) "wand maybe")
(assert (= "PEPE" ((=<> :user {:name string?} (<> maybe) :name string/ascii-upper)
                    user)) "=<> maybe")
(assert (nil? ((=<> :user {:name (>check-all all string? |(string/has-prefix? "o" $))}
                    (<> maybe) :name string/ascii-upper) user)) "=<> maybe then fail")
(assert (= "OPEPE" ((wand :user {:name (>check-all all string? |(string/has-prefix? "o" $))}
                          (<> maybe) :name string/ascii-upper) ouser)) "wand maybe then succ")
(assert (= "OPEPE" ((=<> :user {:name (>check-all all string? |(string/has-prefix? "o" $))}
                         (<> maybe) :name string/ascii-upper) ouser)) "=<> maybe then succ")
(assert (= "PEPE" ((wand :user (<> safe) {:name string?} :name string/ascii-upper)
                    user)) "wand safe succ")
(assert (= "PEPE" ((=<> :user (<> safe) {:name string?} :name string/ascii-upper)
                    user)) "=<> safe succ")
(assert (nil? ((wand :user (<> safe) {:name number?} :name string/ascii-upper)
                user)) "wand safe fail")
(assert (nil? ((=<> :user (<> safe) {:name number?} :name string/ascii-upper)
                user)) "=<> safe fail")
(assert-error "(<> reset)"
              ((wand :user (<> safe) {:name string?} (<> reset) :missing string/ascii-upper)
                user) "wand reset")
(assert-error "(<> reset)"
              ((=<> :user (<> safe) {:name string?} (<> reset) :missing string/ascii-upper)
                user) "=<> reset")
(defn- trace-output?
  ```
  Checks the shape of `wand`/`=<>` trace output without pinning the
  `*current-file*` path it embeds, which varies by invocation directory
  and OS path separator.
  ```
  [out]
  (and (string/find "after point :name base is:\n\"pepe\" \n\n" out)
       (string/find "after point <cfunction string/ascii-upper> base is:\n\"PEPE\" \n\n" out)
       true))

(assert
  (let [[res out] (capture-stderr
                     ((wand :user {:name string?} (<> trace) :name string/ascii-upper) user))]
    (and (= res "PEPE") (trace-output? out)))
  "wand trace")
(assert
  (let [[res out] (capture-stderr
                     ((=<> :user {:name string?} (<> trace) :name string/ascii-upper) user))]
    (and (= res "PEPE") (trace-output? out)))
  "=<> trace")
(assert (= {} ((wand (<> default {}) :user {:name string?} (<> escape) :name string/ascii-upper) user)) "wand default escape")
(assert (= {} ((=<> (<> default {}) :user {:name string?} (<> escape) :name string/ascii-upper) user)) "=<> default escape")
(assert (nil? ((wand (<> default {}) :user (<> reset) {:name string?} (<> escape) :name string/ascii-upper) user)) "wand default escape")
(assert (nil? ((=<> (<> default {}) :user  (<> reset) {:name string?} (<> escape) :name string/ascii-upper) user)) "=<> default escape")
(end-suite)
