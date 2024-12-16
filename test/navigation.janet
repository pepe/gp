(use spork/test spork/misc)
(use ../gp/data/navigation)
(start-suite "Navigation documentation")
(assert-docs "../gp/data/navigation")
(end-suite)

(start-suite "traverse")
(assert (traverse :a :b))
(assert (= "1" ((traverse :a :b) {:a {:b "1"}})))
(assert (=> :a :b))
(assert (= "1" ((=> :a :b) {:a {:b "1"}})))
(end-suite)

(start-suite "points")

(assert
  (= ((=> :projects "0" :name)
       {:projects {"0" {:name "Eleanor"}}}) "Eleanor")
  "get-in")

(assert
  (deep= ((=> :projects values first :tasks values first :name)
           {:projects {"0" {:tasks [{:name "finish"}]}}})
         "finish")
  "with functions")

(assert
  (deep= ((>map-get :title) [{:title "Kamilah"} {:title "Eleanor"}])
         @["Kamilah" "Eleanor"])
  ">map-get")

(assert
  (deep= ((>: :title) [{:title "Kamilah"} {:title "Eleanor"}])
         @["Kamilah" "Eleanor"])
  ">map-get alias")

(assert
  (deep= ((>map type) [@{} @{}]) @[:table :table])
  ">map")

(def collected @[])
(assert (= ((=> (>collect collected (>map-get :title)) values first :id) [{:title "Kamilah" :id "0"} {:title "Eleanor"}]) "0"))
(assert
  (deep= collected @[@["Kamilah" "Eleanor"]])
  "collect")

(assert
  (deep= ((>filter pos?) [-1 10 -3]) @[10])
  "filter")

(assert
  (deep= ((>Y pos?) [-1 10 -3]) @[10])
  "filter alias")

(assert
  ((>check some pos?) [-1 10 -3])
  ">check with some")

(assert
  ((>?? some pos?) [-1 10 -3])
  ">check with some alias")


(assert ((>check-all all number? pos?) 1))

(assert ((>check-all some number? string?) 1))

(assert ((>check-all some number? string?) "1"))

(assert
  (deep= (>flatvals [["finish"] ["start" "add plus"]])
         @["finish" "start" "add plus"])
  ">flatvals")

(assert
  (deep= ((>select-keys :id :title)
           {:id "0" :title "Kamilah" :misc "misc"})
         @{:id "0" :title "Kamilah"})
  ">select-keys")

(assert
  (deep= ((>:: :id :title)
           {:id "0" :title "Kamilah" :misc "misc"})
         @{:id "0" :title "Kamilah"})
  ">select-keys alias")

(assert (do
          (deep= ((>put :state "completed") @{:id "0" :title "Kamilah"})
                 @{:id "0" :title "Kamilah" :state "completed"}))
        ">put state")

(assert (deep= ((>update :counter inc) @{:counter 0})
               @{:counter 1})
        "change-fn")


(assert (do
          (def db @{:guns @[:a :lot]})
          ((=> :guns (>add :rusty)) db)
          (deep= @{:guns @[:a :lot :rusty]} db))
        "add to array")

(assert (do
          (def db @{:guns @[:a :lot]})
          ((=> :guns (>remove 1)) db)
          (deep= @{:guns @[:a]} db))
        "remove from array")

(assert (do
          (def db @{:guns @[:a :lot]})
          ((=> :guns (>find-remove :a)) db)
          (deep= @{:guns @[:lot]} db))
        "remove value from array")

(assert (do
          (def db @{:guns [:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (>limit 2)) db) [:a :lot]))
        "limit tuple")

(assert (do
          (def db @{:guns @[:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (>limit 2)) db) @[:a :lot]))
        "limit array")

(assert (do
          (def db @{:guns "a lot lot lot lot"})
          (deep= ((=> :guns (>limit 5)) db) "a lot"))
        ">limit string")

(assert (do
          (def db @{:guns @"a lot lot lot lot"})
          (deep= ((=> :guns (>limit 5)) db) @"a lot"))
        ">limit buffer")

(assert (do
          (def db @{:guns :a-lot-lot-lot-lot})
          (deep= ((=> :guns (>limit 5)) db) :a-lot))
        ">limit keyword")

(assert (do
          (def db @{:guns 'a-lot-lot-lot-lot})
          (deep= ((=> :guns (>limit 5)) db) 'a-lot))
        ">limit symbol")

(assert (do
          (def db @{:guns @[:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (>limit 7)) db) @[:a :lot :lot :lot :lot]))
        ">limit lenght greater")

(assert (deep= ((>merge) @[@{:a :b} @{:c :d}]) @{:a :b :c :d})
        ">merge default")

(assert (deep= ((>merge {:e :f}) @[@{:a :b} @{:c :d}])
               @{:a :b :c :d :e :f})
        ">merge arg")

(assert (deep= ((>merge-into {:d :e}) @{:a :b}) @{:a :b :d :e})
        ">merge-into")

(assert (deep= ((>clear :a :b) @{:a "a" :b "b" :c "c"})
               @{:c "c"}))

(assert-error "bad path" ((=> values) 1))

(assert
  (string/has-prefix? "Point <function values> errored with:"
                      (try ((=> values) 1) ([e] e)))
  "catch error")

(def changes
  @[{:id 0 "change" "focus"} {:id 1 "change" "new"}
    {:id 2 "change" "new"} {:id 3 "change" "focus"}])

(assert (= (changes 1)
           ((>find-from-start |(= ($ "change") "new")) changes))
        ">find-from-start")

(assert (nil?
          ((>find-from-start |(= ($ "change") "newer")) changes))
        ">find-from-start nil")

(assert (= (changes 2)
           ((>find-from-end |(= ($ "change") "new")) changes))
        ">find-from-end")

(assert (nil?
          ((>find-from-end |(= ($ "change") "newer")) changes))
        ">find-from-end nil")

(assert-no-error "nil base"
                 ((=> 0 :bo :ho) changes))

(assert (nil? ((=> 0 :bo :ho) changes))
        "nil base")

(assert (= (changes 1)
           ((>from-start 1) changes))
        "from-start")

(assert (= (changes 2)
           ((>from-end 1) changes))
        "from-end")

(assert (nil?
          ((>from-end 4) changes))
        "from-end")

(assert (= 3 (length ((>partition-by |($ "change")) changes)))
        "partition-by")

(assert (array? (((>group-by |($ "change")) changes) "new"))
        "group-by")

(assert (array? (((>group-by |($ "change")) changes) "focus"))
        "group-by")

(assert ((=> :c (>if nil? (always true))) {:a :b})
        "on val")

(assert (deep= @[:a] ((>if table? keys) @{:a :b}))
        "on fn")

(assert ((>if nil? (always false) (always true)) @{:a :b})
        "on else")

(assert (deep= @[:a] ((=> (>if (fn [b] false) (always false)
                               (fn [b] (keys b)))) @{:a :b}))
        "on else fn2")
(assert (deep= @[:a] ((=> (>if table? keys)) @{:a :b})))
(assert (deep= @{:a :b} ((=> (>if array? keys)) @{:a :b})))

(array/clear collected)

(assert (deep= @[0] ((=> (<- collected first) (>base collected)) (range 10)))
        ">base")

(array/clear collected)

(assert (deep= @[0] ((=> (<- collected first) (<-> collected)) (range 10)))
        ">base alias")

(assert-error ">assert" ((=> (>assert nil? "must be nil")) true))

(assert-error ">assert" ((=> (>assert nil?)) true))

(assert-no-error ">assert" ((=> (>assert nil? "must be nil")) nil))

(assert-no-error ">assert" ((=> (>assert nil?)) nil))

(assert (deep= ((=> (>map-keys keyword)) @{"a" "b"}) @{:a "b"}) "mapkeys")
(assert (deep= ((=> (>map-vals keyword)) @{"a" "b"}) @{"a" :b}) "mapvals")

(assert (function? >sort-by))
(assert (deep= @[{:value 0} {:value 10}]
               ((=> (>sort-by |(get $ :value))) @[{:value 10} {:value 0}])))

(end-suite)
