(use /gp/data/navigation)

(def db-str
  ```
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
                         :priority 0}}}}}
  ```)
(def db
  ```
  Datastructure to hold the data for to-do list.
  ```
  (parse db-str))

(print "Datastrucure:")
(print db-str)
(print)

(print "Find all tasks:")
(printf "%j" ((=> :projects values (in-all :tasks)) db))
(print)

(print "Find all tasks' names:")
(printf "%j" ((=> :projects values (in-all :tasks) (all-by values) flatten (in-all :name)) db))
(print)

(print "Find high priority task's name:")
(printf "%j" ((=> :projects values (in-all :tasks)
                  (all-by values) flatten
                  (filter-by (=> :priority pos?)) (in-all :name)) db))
(print)

(def c @[])
(defn task-display
  [t [ps]]
  (string (t :name) " " (get-in ps [(t :project) :title])))
(print "Find high priority task's name and title of the project:")
(printf "%j" ((=> :projects (collect c) values (in-all :tasks)
                  (all-by values) flatten
                  (filter-by (=> :priority pos?))
                  (view task-display c)) db))

(print)
