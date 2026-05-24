(use spork/test spork/misc)
(use ../gp/data/navigation)
(use ../gp/data/schema)
(use ../gp/data/magic)
(start-suite "Magic documentation")
(assert-docs "../gp/data/magic")
(end-suite)

(start-suite "wand")
(def user @{:user {:name "pepe"}})
(def ouser @{:user {:name "opepe"}})
(assert wand "Wand macro")
(assert (= "pepe" ((wand :user :name) user)))
(assert (= "PEPE" ((wand :user :name string/ascii-upper) user)))
(assert (= "PEPE" ((wand :user {:name string?} :name string/ascii-upper) user)))
(assert (nil? ((wand :user {:name number?} :name string/ascii-upper) user)))
(assert (= "PEPE" ((wand :user {:name string?} :name string/ascii-upper) user)))
(assert (= {:name "pepe"} ((wand :user {:name string?}) user)))
(assert (nil? ((wand :user {:name string?} (<> escape) :name string/ascii-upper) user)))
(assert (= "PEPE" ((wand :user {:name string?} (<> maybe) :name string/ascii-upper)
                    user)))
(assert (nil? ((wand :user {:name (>check-all all string? |(string/has-prefix? "o" $))}
                     (<> maybe) :name string/ascii-upper) user)))
(assert (= "OPEPE" ((wand :user {:name (>check-all all string? |(string/has-prefix? "o" $))}
                          (<> maybe) :name string/ascii-upper) ouser)))
(assert (= "PEPE" ((wand :user {:name string?} (<> maybe) :name string/ascii-upper)
                    @{:user @{:name "pepe"}})))
(assert (= "PEPE" ((wand :user (<> safe) {:name string?} :name string/ascii-upper)
                    @{:user @{:name "pepe"}})))
(assert (nil? ((wand :user (<> safe) {:name number?} :name string/ascii-upper)
                @{:user @{:name "pepe"}})))
(assert-error "(<> reset)"
              ((wand :user (<> safe) {:name string?} (<> reset) :missing string/ascii-upper)
                @{:user @{:name "pepe"}}))
(macex '(wand :user {:name string?} (<> unknown) :missing string/ascii-upper))
(def out
  (assert
    (= '("PEPE"
          "trace [.\\test\\magic.janet] after point :name base is:\n\"pepe\" \n\ntrace [.\\test\\magic.janet] after point <cfunction string/ascii-upper> base is:\n\"PEPE\" \n\n")
       (capture-stderr
         ((wand :user {:name string?} (<> trace) :name string/ascii-upper) user)))))
(end-suite)
