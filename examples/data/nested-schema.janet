# This example show, how one can use nested validate.
# By default it is not very easy to validate nested
# structures with Manisha. And it is by design, as
# it keeps the design and functionality pretty simple.
# But fear not, we will show you, how you can approach
# this problem.
(use /gp/data/schema)

(def data
  @{:clients
    @{"1" @{:name "me" :uuid "1"
            :projects @{"2" @{:name "shaving" :uuid "2"
                              :tasks @{"3" @{:name "Sunday"
                                             :uuid "3"
                                             :state "complete"}
                                       "4" @{:name "Wednesday"
                                             :uuid "4"
                                             :state "active"}}}
                        "5" @{:name "cooking" :uuid "5"
                              :tasks @{"6" @{:name "noon"
                                             :uuid "6"
                                             :state "active"}
                                       "7" @{:name "evening"
                                             :uuid "7"
                                             :state "active"}}}}}
      "8" @{:name "family" :uuid "8"
            :projects @{"9" @{:name "kidding" :uuid "9"
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

(define-registry
  "Base registry"
  :valid-uuid {:uuid string-number?}
  :present-name {:name present-string?}
  :valid-state {:state (one-of? "active" "complete" "canceled")})

(def task
  (get-in data [:clients "1" :projects "2" :tasks "3"]))

(def task-validator
  (validator table?
             (registry->schema :present-name
                               :valid-uuid
                               :valid-state)))

(printf "validate one task %q results to: %q"
        task (task-validator task))

(def tasks-coll-validator
  (validator table? {values task-validator
                     keys string-number?}))

(def project (get-in data [:clients "1" :projects "2"]))

(def project-validator
  (validator table?
             (registry->schema
               :present-name
               :valid-uuid
               {:tasks tasks-coll-validator})))

(printf "validate one project %q results to: %q"
        project (project-validator project))

(def projects-coll-validator
  (validator table? {values project-validator
                     keys string-number?}))

(def client (get-in data [:clients "1"]))

(def client-validator
  (validator table?
             (registry->schema
               :present-name
               :valid-uuid
               {:projects projects-coll-validator})))

(printf "validate one client %q results to: %q"
        client (client-validator client))

(def clients-validator
  (validator table? {keys string-number?
                     values client-validator}))


(printf "validate clients %q results to: %q"
        (data :clients) (clients-validator (data :clients)))

(def root-validator
  (validator table? {:clients table?
                     values clients-validator}))

(printf "validate whole ds %q results to: %q"
        data (root-validator data))

# As could be seen in this example, it is actually pretty easy
# to validate nested structures, with nested validators.
# It also leads to easier gradual creation of the schema.

