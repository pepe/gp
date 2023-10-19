(use spork/test spork/misc)
(use ../gp/data)

(def s (make Store))

(start-suite "All together")
(:save s
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

(assert (deep= (:transact s :projects values (>: :tasks) flatvals (>Y (??? {:project (eq "1")})))
               @[@{:name "start" :priority 1 :project "1" :uuid "3"}
                 @{:name "add plus" :priority 0 :project "1" :uuid "4"}])
        "querying with flatting")

(:transact s :projects values (>: :tasks) flatvals (map-fn (fn-change :priority inc)) (>: :priority))
(assert (deep= @[1 2 1] (:transact s :projects values (>: :tasks) flatvals (>: :priority)))
        "changing ints")
(end-suite)
