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
  (deep= ((=> :projects values (in-all :title)) db)
         @["Kamilah" "Eleanor"])
  "in-all")


(assert
  (deep= ((=> :projects values
              (in-all :tasks)
              (all-by (in-all :name))) db)
         @[@["finish"] @["start" "add plus"]])
  "all-by")

(assert
  (deep= ((=> :projects values
              (>: :tasks) (>fn (>: :name)) flatten) db)
         @["finish" "start" "add plus"])
  "in-all, all-by aliases")

(assert
  (deep= ((=> :projects values (collect (in-all :title))
              (in-all :tasks) (all-by values) flatten
              (in-all :name)) db)
         @[@["finish" "start" "add plus"] @["Kamilah" "Eleanor"]])
  "collect")

(assert
  (deep= ((=> :projects values
              (in-all :tasks) (all-by values) flatten
              (filter-by |(pos? ($ :priority)))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter")

(assert
  (deep= ((=> :projects values
              (in-all :tasks) (all-by values) flatten
              (>Y |(pos? ($ :priority)))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter alias")

(assert
  (deep= ((=> :projects values
              (in-all :tasks) (all-by values) flatten
              (filter-by (=> :priority pos?))) db)
         @[@{:uuid "3"
             :name "start"
             :priority 1}])
  "filter by =>")

(assert
  (true? ((=> :projects values
              (in-all :tasks) (all-by (in-all :priority)) flatten
              (check some pos?)) db))
  "check with some")

(assert
  (true? ((=> :projects values (in-all :tasks)
              (all-by (in-all :priority)) flatten
              (>?? some pos?)) db))
  "check with some alias")

(assert
  (not ((=> :projects values (in-all :tasks)
            (all-by (in-all :priority)) flatten
            (check some neg?)) db))
  "check with some falsey")

(assert
  (deep= ((=> :projects values
              (filter-by
                (=> :tasks values
                    (in-all :priority)
                    (check some pos?)))) db)
         @[@{:uuid "1" :title "Eleanor"
             :tasks
             @{"3" @{:name "start" :priority 1 :uuid "3"}
               "4" @{:name "add plus" :priority 0 :uuid "4"}}}])
  "filter by => with check")

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

(assert
  (deep= ((=> (collect (=> :priorities)) :projects "1" (collect (=> :title))
              :tasks values (view display-name)) db)
         @[@["@Eleanor #3 - start is high priority"
             "@Eleanor #4 - add plus is low priority"]
           @{0 "low" 1 "high"}
           "Eleanor"])
  "view with collected")

(assert
  (deep= ((=> (collect (=> :priorities)) :projects "1" (collect (=> :title))
              :tasks values (view display-name) drop-collected) db)
         @["@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "view with collected then drop")

(assert
  (deep= ((=> (<- (=> :priorities)) :projects "1" (<- (=> :title))
              :tasks values (<o> display-name) <x) db)
         @["@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "view with collected then drop with aliases")

(defn display-name [ts [priorities ps]]
  (string/format "@%s #%s - %s is %s priority"
                 (get-in ps [(ts :project) :title]) (ts :uuid) (ts :name)
                 (priorities (ts :priority))))

(assert
  (deep= ((=> (<- (=> :priorities)) :projects (<-)
              values (>: :tasks) (>fn values) flatten
              (<o> display-name) <x) db)
         @["@Kamilah #2 - finish is low priority"
           "@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "view all with collected then drop with aliases")

(assert
  (deep= ((=> (<- (=> :priorities)) :projects (<-)
              values (>: :tasks) flatvals
              (<o> display-name) <x) db)
         @["@Kamilah #2 - finish is low priority"
           "@Eleanor #3 - start is high priority"
           "@Eleanor #4 - add plus is low priority"])
  "flatvals")

(assert
  (deep= ((=> :projects values (all-by (select :uuid :title))) db)
         @[@{:uuid "0" :title "Kamilah"} @{:uuid "1" :title "Eleanor"}])
  "select")

(assert
  (deep= ((=> :projects values (all-by (>:: :uuid :title))) db)
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

(assert (do
          (defn mul [n [m]] (* n m))
          (def h @{true (range 3) false (range 3 6) :mul 10})
          (deep= ((=> (collect (=> :mul))
                      (fn-change true (view mul))
                      (fn-change false (view mul)) drop-collected) h)
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

(assert (deep= ((=> (merged)) @[@{:a :b} @{:c :d}])
               @{:a :b :c :d})
        "merged default")

(assert (deep= ((=> (merged {:e :f})) @[@{:a :b} @{:c :d}])
               @{:a :b :c :d :e :f})
        "merged arg")

(assert (deep= ((=> (into {:d :e})) @{:a :b}) @{:a :b :d :e})
        "into")

(assert-error "bad path" ((=> values) 1))

(assert
  (= (try ((=> values) 1) ([e] e))
     "Point <function values> errored with: expected iterable type, got 1")
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

(assert
  (string/has-prefix?
    "Elapsed: 0."
    ((capture-stderr
       ((=> (<- (=> :priorities)) trace-elapsed
            :projects (<-) values (>: :tasks) flatvals
            drop-elapsed (<o> display-name) trace-elapsed <x) db)) 1))
  "trace elapsed time")

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

(assert (deep= ((=> (const "HOHO")) @{}) @[@{} "HOHO"])
        "const")

(assert ((=> :c (on nil? true)) {:a :b})
        "on val")

(assert (deep= @[:a] ((=> (on table? keys)) @{:a :b}))
        "on fn")

(assert ((=> (on (fn [b c] true) true)) @{:a :b})
        "on collected")

(assert ((=> (on nil? false true)) @{:a :b})
        "on else")

(assert (deep= @[:a] ((=> (on nil? false keys)) @{:a :b}))
        "on else fn")

(assert (deep= @[:a] ((=> (on (fn [b c] false)
                              false (fn [b c] (keys b)))) @{:a :b}))
        "on else fn2")

(assert (deep= @[@[0] 0] ((=> (<- first) collected->base) (range 10)))
        "collected->base")

(assert (deep= @[@[0] 0] ((=> (<- first) <->) (range 10)))
        "collected->base")

(assert-error "asserted" ((=> (asserted nil? "must be nil")) true))

(assert-error "asserted" ((=> (asserted nil?)) true))

(assert-no-error "asserted" ((=> (asserted nil? "must be nil")) nil))

(assert-no-error "asserted" ((=> (asserted nil?)) nil))

(assert (deep= ((=> (mapkeys keyword)) @{"a" "b"}) @{:a "b"}) "mapkeys")
(assert (deep= ((=> (mapvals keyword)) @{"a" "b"}) @{"a" :b}) "mapvals")

(assert (deep= ((=> :projects
                    (<- (=> (>: :tasks) (>fn (>: :name))))
                    (>: :title) combine drop-collected) db)
               @{"Eleanor" @["start" "add plus"] "Kamilah" @["finish"]})
        "combine")

(assert (deep= ((=> :projects
                    (<- (=> (>: :tasks) (>fn (>: :name))))
                    (>: :title) concat-collected) db)
                @["Kamilah" "Eleanor" @[@["finish"] @["start" "add plus"]]])
        "concat")

(assert (deep= ((=> :projects
                    (<- (=> (>: :tasks) (>fn (>: :name))))
                    (>: :title) concat-collected flatten) db)
                @["Kamilah" "Eleanor" "finish" "start" "add plus"])
        "concat")

(end-suite)
