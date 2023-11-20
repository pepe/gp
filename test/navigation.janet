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
(def db
  @{:projects
    @{"0" @{:uuid "0" :title "Kamilah"
            :tasks @{"2" @{:uuid "2"
                           :name "finish"
                           :priority 0}}}
      "1" @{:uuid "1" :title "Eleanor"
            :tasks @{"3" @{:uuid "3"
                           :name "start"
                           :priority 1}
                     "4" @{:uuid "4"
                           :name "add plus"
                           :priority 0}}}}})
(assert
  (= ((=> :projects "0" :uuid) db) "0")
  "get-in")

(assert
  (deep= ((=> :projects values) db)
         @[@{:uuid "0" :title "Kamilah"
             :tasks @{"2" @{:uuid "2"
                            :name "finish"
                            :priority 0}}}
           @{:uuid "1" :title "Eleanor"
             :tasks @{"3" @{:uuid "3"
                            :name "start"
                            :priority 1}
                      "4" @{:uuid "4"
                            :name "add plus"
                            :priority 0}}}])
  "with function")

(assert
  (deep= ((=> :projects values (map-in :title)) db)
         @["Kamilah" "Eleanor"])
  "map-in")


(assert
  (deep= ((=> :projects values
              (map-in :tasks)
              (map-fn (map-in :name))) db)
         @[@["finish"] @["start" "add plus"]])
  "map-fn")

(assert
  (deep= ((=> :projects values
              (>: :tasks) (>fn (>: :name)) flatten) db)
         @["finish" "start" "add plus"])
  "map-in, map-fn aliases")

(def collected @[])
(assert
  (deep= ((=> :projects values (collect collected (map-in :title))
              (map-in :tasks) (map-fn values) flatten
              (map-in :name)) db)
         @["finish" "start" "add plus"])
  "collect")

(assert
  (deep= ((=> :projects values
              (map-in :tasks) (map-fn values) flatten
              (filter-by |(pos? ($ :priority)))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter")

(assert
  (deep= ((=> :projects values
              (map-in :tasks) (map-fn values) flatten
              (>Y |(pos? ($ :priority)))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter alias")

(assert
  (deep= ((=> :projects values
              (map-in :tasks) (map-fn values) flatten
              (filter-by (=> :priority pos?))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter by =>")

(assert
  (true? ((=> :projects values
              (map-in :tasks) (map-fn (map-in :priority)) flatten
              (check some pos?)) db))
  "check with some")

(assert
  (true? ((=> :projects values (map-in :tasks)
              (map-fn (map-in :priority)) flatten
              (>?? some pos?)) db))
  "check with some alias")

(assert
  (not ((=> :projects values (map-in :tasks)
            (map-fn (map-in :priority)) flatten
            (check some neg?)) db))
  "check with some falsey")

(assert
  (deep= ((=> :projects values
              (filter-by
                (=> :tasks values
                    (map-in :priority)
                    (check some pos?)))) db)
         @[@{:uuid "1" :title "Eleanor"
             :tasks
             @{"3" @{:name "start" :priority 1 :uuid "3"}
               "4" @{:name "add plus" :priority 0 :uuid "4"}}}])
  "filter by => with check")


(assert ((conform all number? pos?) 1))

(assert ((conform some number? string?) 1))

(def db
  @{:priorities
    @{0 "low"
      1 "high"}
    :projects
    @{"0" @{:uuid "0" :title "Kamilah"
            :tasks @{"2" @{:uuid "2"
                           :name "finish"
                           :project "0"
                           :priority 0}}}
      "1" @{:uuid "1" :title "Eleanor"
            :tasks @{"3" @{:uuid "3"
                           :name "start"
                           :project "1"
                           :priority 1}
                     "4" @{:uuid "4"
                           :name "add plus"
                           :project "1"
                           :priority 0}}}}})

(defn display-name [ts [priorities pt]]
  (string/format "@%s #%s - %s is %s priority"
                 pt (ts :uuid) (ts :name) (priorities (ts :priority))))

(array/clear collected)

(assert
  (deep= ((=> (collect collected (=> :priorities)) :projects "1" (collect collected (=> :title))
              :tasks values (map-fn display-name collected)) db)
         @["@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "map-fn with collected")

(array/clear collected)

(assert
  (deep= ((=> (collect collected (=> :priorities)) :projects "1" (collect collected (=> :title))
              :tasks values (map-fn display-name collected)) db)
         @["@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "map-fn with collected then drop")

(array/clear collected)

(assert
  (deep= ((=> (<- collected (=> :priorities)) :projects "1" (<- collected (=> :title))
              :tasks values (>fn display-name collected)) db)
         @["@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "map-fn with collected then drop with aliases")

(defn display-name [ts [priorities ps]]
  (string/format "@%s #%s - %s is %s priority"
                 (get-in ps [(ts :project) :title]) (ts :uuid) (ts :name)
                 (priorities (ts :priority))))

(array/clear collected)

(assert
  (deep= ((=> (<- collected (=> :priorities)) :projects (<- collected)
              values (>: :tasks) (>fn values) flatten
              (>fn display-name collected)) db)
         @["@Kamilah #2 - finish is low priority"
           "@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "map-fn all with collected then drop with aliases")

(array/clear collected)

(assert
  (deep= ((=> (<- collected (=> :priorities)) :projects (<- collected)
              values (>: :tasks) flatvals
              (>fn display-name collected)) db)
         @["@Kamilah #2 - finish is low priority"
           "@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "flatvals")

(assert
  (deep= ((=> :projects values (map-fn (select :uuid :title))) db)
         @[@{:uuid "0" :title "Kamilah"} @{:uuid "1" :title "Eleanor"}])
  "select")

(assert
  (deep= ((=> :projects values (map-fn (>:: :uuid :title))) db)
         @[@{:uuid "0" :title "Kamilah"} @{:uuid "1" :title "Eleanor"}])
  "select alias")

(assert (do ((=> :projects "0" :tasks "2"
                 (change :state "completed")) db)
          (deep= ((=> :projects "0" :tasks "2" :state) db)
                 "completed"))
        "mutate db - change state")

(assert (deep= ((=> (fn-change :counter inc)) @{:counter 0})
               @{:counter 1})
        "change-fn")

(array/clear collected)

(assert (do
          (defn mul [n [m]] (* n m))
          (def h @{true (range 3) false (range 3 6) :mul 10})
          (deep= ((=> (collect collected (=> :mul))
                      (fn-change true (map-fn mul collected))
                      (fn-change false (map-fn mul collected))) h)
                 @{false @[30 40 50] true @[0 10 20] :mul 10}))
        "fn-change with collected")

(assert (do ((=> :projects "0" :tasks
                 (change "5" @{:uuid "5"
                               :name "add minus"
                               :project "1"
                               :priority 0})) db)
          (deep= ((=> :projects "0" :tasks "5") db)
                 @{:uuid "5"
                   :name "add minus"
                   :project "1"
                   :priority 0}))
        "mutate db - add task")


(assert (do
          (def db @{:guns @[:a :lot]})
          ((=> :guns (add :rusty)) db)
          (deep= @{:guns @[:a :lot :rusty]} db))
        "add to array")

(assert (do
          (def db @{:guns @[:a :lot]})
          ((=> :guns (remove :a)) db)
          (deep= @{:guns @[:lot]} db))
        "remove from array")

(assert (do
          (def db @{:guns [:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (limit 2)) db) [:a :lot]))
        "limit tuple")

(assert (do
          (def db @{:guns @[:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (limit 2)) db) @[:a :lot]))
        "limit array")

(assert (do
          (def db @{:guns "a lot lot lot lot"})
          (deep= ((=> :guns (limit 5)) db) "a lot"))
        "limit string")

(assert (do
          (def db @{:guns @"a lot lot lot lot"})
          (deep= ((=> :guns (limit 5)) db) @"a lot"))
        "limit buffer")

(assert (do
          (def db @{:guns :a-lot-lot-lot-lot})
          (deep= ((=> :guns (limit 5)) db) :a-lot))
        "limit keyword")

(assert (do
          (def db @{:guns 'a-lot-lot-lot-lot})
          (deep= ((=> :guns (limit 5)) db) 'a-lot))
        "limit symbol")

(assert (do
          (def db @{:guns @[:a :lot :lot :lot :lot]})
          (deep= ((=> :guns (limit 7)) db) @[:a :lot :lot :lot :lot]))
        "limit lenght greater")

(assert (deep= ((=> (merge-all)) @[@{:a :b} @{:c :d}])
               @{:a :b :c :d})
        "merge-all default")

(assert (deep= ((=> (merge-all {:e :f})) @[@{:a :b} @{:c :d}])
               @{:a :b :c :d :e :f})
        "merge-all arg")

(assert (deep= ((=> (into {:d :e})) @{:a :b}) @{:a :b :d :e})
        "into")

(assert-error "bad path" ((=> values) 1))

(assert
  (string/has-prefix? "Point <function values> errored with:"
                      (try ((=> values) 1) ([e] e)))
  "catch error")

(def db
  @{:priorities
    @{0 "low"
      1 "high"}
    :projects
    @{"0" @{:uuid "0" :title "Kamilah"
            :tasks @{"2" @{:uuid "2"
                           :name "finish"
                           :project "0"
                           :priority 0}}}
      "1" @{:uuid "1" :title "Eleanor"
            :tasks @{"3" @{:uuid "3"
                           :name "start"
                           :project "1"
                           :priority 1}
                     "4" @{:uuid "4"
                           :name "add plus"
                           :project "1"
                           :priority 0}}}}})

(array/clear collected)

(def changes
  @[{:id 0 "change" "focus"} {:id 1 "change" "new"}
    {:id 2 "change" "new"} {:id 3 "change" "focus"}])

(assert (= (changes 1)
           ((=> (find-from-start |(= ($ "change") "new"))) changes))
        "find-from-start")

(assert (nil?
          ((=> (find-from-start |(= ($ "change") "newer"))) changes))
        "find-from-start nil")

(assert (= (changes 2)
           ((=> (find-from-end |(= ($ "change") "new"))) changes))
        "find-from-end")

(assert (nil?
          ((=> (find-from-end |(= ($ "change") "newer"))) changes))
        "find-from-end nil")

(assert-no-error "nil base"
                 ((=> 0 :bo :ho) changes))

(assert (nil? ((=> 0 :bo :ho) changes))
        "nil base")

(assert (= (changes 1)
           ((=> (from-start 1)) changes))
        "from-start")

(assert (= (changes 2)
           ((=> (from-end 1)) changes))
        "from-end")

(assert (nil?
          ((=> (from-end 4)) changes))
        "from-end")

(assert (= 3 (length ((=> (partitioned-by |($ "change"))) changes)))
        "partition-by")

(assert (array? (((=> (grouped-by |($ "change"))) changes) "new"))
        "group-by")

(assert (array? (((=> (grouped-by |($ "change"))) changes) "focus"))
        "group-by")

(assert ((=> :c (on nil? true)) {:a :b})
        "on val")

(assert (deep= @[:a] ((=> (on table? keys)) @{:a :b}))
        "on fn")

(assert ((=> (on nil? false true)) @{:a :b})
        "on else")

(assert (deep= @[:a] ((=> (on nil? false keys)) @{:a :b}))
        "on else fn")

(assert (deep= @[:a] ((=> (on (fn [b] false) false
                              (fn [b] (keys b)))) @{:a :b}))
        "on else fn2")

(array/clear collected)

(assert (deep= @[0] ((=> (<- collected first) (->base collected)) (range 10)))
        "->base")

(array/clear collected)

(assert (deep= @[0] ((=> (<- collected first) (<-> collected)) (range 10)))
        "collected->base alias")

(assert-error "asserted" ((=> (asserted nil? "must be nil")) true))

(assert-error "asserted" ((=> (asserted nil?)) true))

(assert-no-error "asserted" ((=> (asserted nil? "must be nil")) nil))

(assert-no-error "asserted" ((=> (asserted nil?)) nil))

(assert (deep= ((=> (mapkeys keyword)) @{"a" "b"}) @{:a "b"}) "mapkeys")
(assert (deep= ((=> (mapvals keyword)) @{"a" "b"}) @{"a" :b}) "mapvals")

(end-suite)
