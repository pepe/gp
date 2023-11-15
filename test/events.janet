(use spork/test)

(use ../gp/events)

(defmacro assert-with-manager [msg & forms]
  ~(assert
     (let [manager (,make-manager)]
       ,;forms)
     ,msg))

(start-suite "Manager documentation")
(assert-docs "../gp/events")
(end-suite)

(start-suite "Manager")
(assert-no-error (make-manager) "initialize")

(assert-no-error "initialize with state" (make-manager @{:counter 1}))

(assert-error "init-manager with wrong state" (make-manager {:counter 1}))
(end-suite)

(start-suite "Events")
# Events
(assert
  (let [a (make-event {:update (fn [_ state] state)})]
    (and (a :update)
         (false? (a :watch))
         (false? (a :effect))
         (= (a :name) "anonymous")))
  "make-event")

(define-event TestEvent {:update (fn [_ state] state)})
(assert (and (TestEvent :update)
             (false? (TestEvent :watch))
             (false? (TestEvent :effect))
             (= (TestEvent :name) "TestEvent"))
        "define-event")
(assert (valid? TestEvent) "valid?")

(define-event TestDocEvent "docstring" {:update (fn [_ state] state)})
(assert (=
          (last (capture-stdout (doc TestDocEvent)))
          "\n\n    table\n    test/events.janet on line 41, column 1\n\n
    docstring\n\n\n")
        "define-event docstring")
# Transact
(define-event TestUpdateEvent
  {:update (fn [_ state] (put state :test "Test"))})

(define-event TesttUpdateEvent
  {:update (fn [_ state] (update state :test |(string $ "t")))})

(assert-with-manager
  "one update event"
  (:transact manager TestUpdateEvent)
  (deep= (manager :state) @{:test "Test"}))
(assert-with-manager
  "one watch event"
  (define-event TestWatchEvent {:watch (fn [_ _ _] TestUpdateEvent)})
  (:transact manager TestWatchEvent)
  (deep= (manager :state) @{:test "Test"}))
(assert-with-manager
  "one effect event"
  (var ok false)
  (define-event TestEffectEvent {:effect (fn [_ state _] (set ok true))})
  (:transact manager TestEffectEvent)
  ok)
(assert-with-manager
  "many watch events"
  (define-event
    TestWatchEvent
    {:watch (fn [_ _ _]
              [TestUpdateEvent TesttUpdateEvent TesttUpdateEvent])})
  (:transact manager TestWatchEvent)
  (deep= (manager :state) @{:test "Testtt"}))
(assert-with-manager
  "combined event"
  (var ok false)
  (define-event
    CombinedEvent
    {:update (fn [_ state] (put state :test "Test"))
     :watch (fn [_ _ _] TesttUpdateEvent)
     :effect (fn [_ _ _] (set ok true))})
  (:transact manager CombinedEvent)
  (and ok (deep= (manager :state) @{:test "Testt"})))
(assert-with-manager
  "multi-yield fiber event"
  (define-event TestFiberEvent
    {:watch
     (fn [_ _ _]
       (coro
         (yield TestUpdateEvent)
         (for _ 0 5 (yield TesttUpdateEvent))
         (yield TesttUpdateEvent)))})
  (:transact manager TestFiberEvent)
  (deep= (manager :state) @{:test "Testtttttt"}))
(assert-with-manager
  "thread event"
  (define-event RandUpEvent
    {:update (fn [_ state]
               (update state :test |(+ (math/random) $)))})
  (define-event ThreadEvent
    {:watch
     (fn [_ state _]
       (def res
         @[(make-update (fn [_ state] (put state :test 0)) "reset")])
       (def chan (ev/thread-chan))
       (var threads 100)
       (repeat
         threads (ev/thread
                   (fiber-fn :t (ev/give-supervisor :rand RandUpEvent))
                   nil :n chan))
       (while (pos? threads)
         (match (ev/take chan)
           [:rand event]
           (do
             (array/push res (make-event event))
             (-- threads))))
       res)})
  (:transact manager ThreadEvent)
  (< 50 ((manager :state) :test)))
(assert-with-manager
  "invalid event"
  (try (:transact manager {})
    ([err] (string/has-prefix? "Only Events are transactable." err))))
(assert-with-manager
  "watch invalid event"
  (try
    (:transact manager (make-event {:watch (fn [_ _ _] {})}))
    ([err]
      (string/has-prefix?
        "Only Event, Array of Events and Fiber are watchable. Got:"
        err))))
(assert-with-manager
  "watch erroring update event"
  (try
    (:transact manager
               (make-event
                 {:update (fn [_ _] (error "Bad thing!"))} "bad update"))
    ([err]
      (= ":update failed for bad update with error: Bad thing!" err))))
(assert-with-manager
  "watch erroring watch event"
  (try
    (:transact manager
               (make-event
                 {:watch (fn [_ _ _] (error "Bad thing!"))} "bad watch"))
    ([err]
      (= ":watch failed for bad watch with error: Bad thing!" err))))
(assert-with-manager
  "watch erroring effect event"
  (try
    (:transact manager
               (make-event
                 {:effect (fn [_ _ _] (error "Bad thing!"))} "bad effect"))
    ([err]
      (= ":effect failed for bad effect with error: Bad thing!" err))))

# producer
(assert-with-manager
  "producer"
  (define-event TestCocoonEvent
    {:watch
     (fn [_ _ _]
       (producer
         (produce TestUpdateEvent TesttUpdateEvent)
         :product))})
  (:transact manager TestCocoonEvent)
  (deep= @[@{:test "Testt"} :product] (:await manager)))

(assert-with-manager
  "thread-producer"
  (define-event TestThreadCocoonEvent
    {:watch
     (fn [_ _ _]
       (thread-producer
         (produce TesttUpdateEvent)
         :product))})
  (:transact manager TestUpdateEvent TestThreadCocoonEvent TestThreadCocoonEvent)
  (deep= @[@{:test "Testtt"} :product :product] (:await manager)))

# on-error
(assert-error
  "on-error keyword"
  (make-manager @{} :on-error))

(assert-no-error
  "on-error function"
  (var err nil)
  (def manager
    (make-manager
      @{}
      (fn on-error [_ msg]
        (set err msg))))
  (def event (make-event {:update (fn [&] (error "So bad!"))} "error-update"))
  (:transact manager event)
  (assert
    (match err
      [:update event (f (fiber? f))] true
      false)))

# watchable nil
(assert-with-manager
  "watchable nil"
  (define-watch NilWatchable [&] nil)
  (:transact manager NilWatchable)
  (empty? (manager :state)))

(end-suite)

(start-suite "Events, Spys and Boxes")

(assert-with-manager
  "make-update"
  (:transact manager (make-update (fn [_ e] (put e :test "Test"))))
  (deep= (manager :state) @{:test "Test"}))

(assert-with-manager
  "make-effect"
  (match (capture-stdout
           (:transact manager (make-effect (fn [&] (prin "Defined")))))
    [manager "Defined"] (deep= (manager :state) @{})))

(assert-with-manager
  "make-watch"
  (define-update TestUpdateDefine [_ e]
    (put e :test "Test"))
  (:transact manager (make-watch (fn [&] TestUpdateDefine)))
  (deep= (manager :state) @{:test "Test"}))

(assert-with-manager
  "define-update"
  (define-update TestUpdateDefine [_ e]
    (put e :test "Test"))
  (:transact manager TestUpdateDefine)
  (deep= (manager :state) @{:test "Test"}))

(define-update TestUpdateDefineDoc "docstring" [_ e]
  (put e :test "Test"))

(assert
  "define-update docstring"
  (= (last (capture-stdout (doc TestUpdateDefineDoc)))
     "\n\n    table\n    test/suite1.janet on line 33, column 1\n\n
   docstring\n\n\n"))

(assert-with-manager
  "define-effect"
  (define-effect TestEffectDefine [&]
    (prin "Defined"))
  (match (capture-stdout (:transact manager TestEffectDefine))
    [manager "Defined"] (deep= (manager :state) @{})))

(assert-with-manager
  "define-watch"
  (define-update TestUpdateDefine [_ e]
    (put e :test "Test"))
  (define-watch TestUpdateWatch [&]
    TestUpdateDefine)
  (:transact manager TestUpdateWatch)
  (deep= (manager :state) @{:test "Test"}))
(end-suite)
