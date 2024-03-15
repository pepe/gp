# This example show, how one can use nested validate.
# By default it is not very easy to validate nested
# structures with Manisha. And it is by design, as
# it keeps the design and functionality pretty simple.
# But fear not, we will show you, how you can approach
# this problem.
(import /gp/data/schema :prefix "" :export true)
(import /gp/data/navigation :prefix "" :export true)
 
(def data
  @{:clients
    @{"1" @{:name "me"
            :projects
            @{"2" @{:name "shaving"
                    :tasks @{"3" @{:name "Sunday"

                                   :state "complete"}
                             "4" @{:name "Wednesday"

                                   :state "active"}}}
              "5" @{:name "cooking"
                    :tasks @{"6" @{:name "noon"

                                   :state "active"}
                             "7" @{:name "evening"

                                   :state "active"}}}}}
      "8" @{:name "family"
            :projects
            @{"9" @{:name "kidding"
                    :tasks @{"10" @{:name "big"
                                    :uuid "10"
                                    :state "canceled"}
                             "11" @{:name "small"
                                    :uuid "11"
                                    :state "active"}}}
              "12" @{:name "enjoying" :uuid "12"
                     :tasks @{"13" @{:name "soon"
                                     :uuid "13"
                                     :state "active"}
                              "14" @{:name "late"
                                     :uuid "14"
                                     :state "active"}}}}}}})

(def?! present-name {:name present-string?})
(def?! valid-state {:state (?one-of "active" "complete" "canceled")})
(def?! string-keys {keys (>check all string-number?)})

(def task
  (get-in data [:clients "1" :projects "2" :tasks "3"]))

(def?! task
  table? present-name? valid-state?)

(printf "validate one task %q results to: %q"
        task (task? task))

(def?! tasks
  table? string-keys? {values (>check all task?)})

(def project (get-in data [:clients "1" :projects "2"]))

(def?! project
  table? present-name? {:tasks tasks?})

(printf "validate one project %q results to: %q"
        project (project? project))

(def?! projects
  table? string-keys? {values (>check all project?)})

(def client (get-in data [:clients "1"]))

(def?! client
  table? present-name?
  {:projects projects?})

(printf "validate one client %q results to: %q"
        client (client? client))

(def?! clients
  table? string-keys? {values (>check all client?)})


(printf "validate clients %q results to: %q"
        (data :clients) (clients? (data :clients)))

(def?! root
  table? {:clients clients?})

(printf "validate whole ds %q results to: %q"
        data (root? data))

# As could be seen in this example, it is easy
# to validate nested structures, with nested validators.
# It also leads to easier gradual creation of the schema.

