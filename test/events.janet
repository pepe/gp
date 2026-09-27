(use spork/test)

(use ../gp/events)

(defmacro with-manager [& forms]
  ~(let [manager (,make-manager)]
     ,;forms))

(defmacro assert-with-manager [msg & forms]
  ~(assert
     (with-manager ,;forms)
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
(assert (string/has-suffix?
          "docstring\n\n\n"
          (last (capture-stdout (doc TestDocEvent))))
        "define-event docstring")
(end-suite)

(start-suite "Transacting")
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
  "one watch event valid"
  (define-event TestWatchEvent {:watch TestUpdateEvent})
  (:transact manager TestWatchEvent)
  (deep= (manager :state) @{:test "Test"}))
(assert-with-manager
  "one watch event indexed"
  (define-event TestWatchEvent {:watch [TestUpdateEvent]})
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
  (define-event CombinedEvent
    {:update (fn [_ state] (put state :test "Test"))
     :watch (fn [_ _ _] TesttUpdateEvent)
     :effect (fn [_ _ _] (set ok true))})
  (:transact manager CombinedEvent)
  (and ok (deep= (manager :state) @{:test "Testt"})))
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
(with-manager
  (define-event TestFiberEvent
    {:watch
     (fn [_ _ _]
       (coro
         (yield TestUpdateEvent)))})
  (assert-error "Yielding in the flow"
                (:transact manager TestFiberEvent)))
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
(assert-with-manager
  "watchable nil"
  (define-watch NilWatchable [&] nil)
  (:transact manager NilWatchable)
  (empty? (manager :state)))
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
(end-suite)

(start-suite "Producers")
(assert-with-manager
  "producer"
  (define-event TestProducerEvent
    {:watch
     (fn [_ _ _]
       (producer
         (produce TestUpdateEvent TesttUpdateEvent)
         :product))})
  (:transact manager TestProducerEvent)
  (deep= @[@{:test "Testt"} :product] (:await manager)))
# A Producer that dies is finished. Counted as anything else, `:_producers`
# never falls to zero and `await` waits on it for the life of the process.
(assert-with-manager
  "a dying producer still finishes"
  (define-event TestFailingProducerEvent
    {:watch
     (fn [_ _ _]
       (producer (error "producer blew up")))})
  (:transact manager TestFailingProducerEvent)
  (deep= @[@{} :error] (:await manager)))
# Waiting for a Producer must leave nothing behind. Janet roots a fiber
# that waits on a thread channel and never unroots it when an `ev/select`
# is answered by another channel, and since 54fbd760 every nested resume
# scans those roots. Waiting on the thread flow for every event made each
# later `protect` slower by one leaked root: 85us instead of 0.5us after a
# day of heartbeats.
(defn- resume-cost []
  (def start (os/clock :monotonic))
  (repeat 2000 (resume (fiber/new (fn [] 1) :i)))
  (- (os/clock :monotonic) start))
(def fresh-resume-cost (resume-cost))
(assert-with-manager
  "waiting for many products leaves fibers as cheap as they were"
  (define-event TestManyProductsEvent
    {:watch
     (fn [_ _ _]
       (producer
         # Sleeping lets the Manager drain the flow and wait again.
         (repeat 20000 (produce TestUpdateEvent) (ev/sleep 0))
         :product))})
  (:transact manager TestManyProductsEvent)
  (:await manager)
  (< (resume-cost) (+ (* 5 fresh-resume-cost) 0.002)))
(assert-with-manager
  "thread-producer"
  (define-event TestThreadProducerEvent
    {:watch
     (fn [_ _ _]
       (thread-producer
         (produce TesttUpdateEvent)
         :product))})
  (:transact manager TestUpdateEvent TestThreadProducerEvent TestThreadProducerEvent)
  (deep= @[@{:test "Testtt"} :product :product] (:await manager)))
# The thread flow is waited on only while a thread producer runs, so that
# a Manager with none never waits on a thread channel at all.
(assert-with-manager
  "finished thread producers leave the flow alone"
  (define-event TestThreadProducerEvent
    {:watch (fn [_ _ _] (thread-producer :product))})
  (:transact manager TestThreadProducerEvent TestThreadProducerEvent)
  (:await manager)
  (zero? (manager :_thread-producers)))
# A thread producer started while the Manager waits on the flow alone
# must be heard at once, not only when something else speaks.
(assert-with-manager
  "a thread producer is heard while the Manager waits"
  (define-event TestThreadProducerEvent
    {:watch
     (fn [_ _ _]
       (thread-producer
         (produce TesttUpdateEvent)
         :product))})
  (define-event TestSlowProducerEvent
    {:watch
     (fn [_ _ _]
       (producer
         (ev/sleep 0.3)
         ((manager :state) :test)))})
  (:transact manager TestUpdateEvent TestSlowProducerEvent)
  (ev/spawn
    (ev/sleep 0.05)
    (:transact manager TestThreadProducerEvent))
  (def results (:await manager))
  # The slow producer finishes last, and reads the state the thread left.
  (= "Testt" (last results)))
# Under load, with a producer on the flow beside it, a thread producer that
# keeps the Manager waiting between its events. Waiting with `ev/select`
# over both flows, the Manager hung (a give lost inside the select) or lost
# the thread's last events (its `:ok` overtook them after a stale wait).
(def load-n 3000)
(define-event ThreadLoadCount
  {:update (fn [_ state] (update state :thread inc))})
(define-event PlainLoadCount
  {:update (fn [_ state] (update state :plain inc))})
(define-event ThreadLoad
  {:watch
   (fn [_ _ _]
     (thread-producer
       (repeat load-n
         (produce ThreadLoadCount)
         (var x 0)
         (repeat 500 (++ x)))
       :thread))})
(define-event PlainLoad
  {:watch
   (fn [_ _ _]
     (producer
       (repeat load-n
         (produce PlainLoadCount)
         (ev/sleep 0.0001))
       :plain))})
(repeat 5
  (def manager (make-manager @{:thread 0 :plain 0}))
  (def results
    (try
      (ev/with-deadline 30
        (:transact manager ThreadLoad PlainLoad)
        (:await manager))
      ([err] err)))
  (assert (and (indexed? results)
               (deep= @{:thread load-n :plain load-n} (first results))
               (deep= @[:plain :thread] (sort (array/slice results 1))))
          (string/format "thread producer under load: %q" results)))
(assert-with-manager
  "producer exit"
  (define-event TestProducerEvent
    {:watch
     (fn [_ _ _]
       (producer
         (produce TestUpdateEvent)
         (exit)
         (produce TesttUpdateEvent)
         (ev/sleep 10)
         :product))})
  (:transact manager TestProducerEvent)
  (deep= (:await manager) @[@{:test "Test"} :exit]))
(end-suite)

(start-suite "On error")
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

# spys
(assert-with-manager
  "spys"
  (var updated false)
  (define-update Zero [_ e] (put e :counter 0))
  (define-update Increment [_ e] (update e :counter inc))
  (define-effect Log [&] (set updated true))
  (define-event TestSpyEvent
    {:spy
     (fn [_ oe]
       (make-snoop
         @{:old-counter (oe :counter)
           :snoop (fn [self ne spys event]
                    (when (> (ne :counter) (self :old-counter))
                      (set (self :old-counter) (ne :counter))
                      Log))}))})
  (:transact manager Zero TestSpyEvent Increment)
  updated)

(assert-with-manager
  "spys removing"
  (var updated 0)
  (define-update Zero [_ e] (put e :counter 0))
  (define-update Increment [_ e] (update e :counter inc))
  (define-effect Log [&] (++ updated))
  (define-event TestSpyEvent
    {:spy
     (fn [_ oe]
       (make-snoop
         @{:old-counter (oe :counter)
           :snoop (fn [self ne spys event]
                    (when (> (ne :counter) (self :old-counter))
                      (set (self :old-counter) (ne :counter))
                      (array/clear spys)
                      Log))}))})
  (:transact manager Zero TestSpyEvent Increment Increment Increment)
  (one? updated))

# watchable nil
(assert-with-manager
  "watchable nil"
  (define-watch NilWatchable [&] nil)
  (:transact manager NilWatchable)
  (empty? (manager :state)))

(end-suite)

(start-suite "Events, Spys and Boxes")

(assert-with-manager
  "make-spy"
  (var updated false)
  (define-update Zero [_ e] (put e :counter 0))
  (define-update Increment [_ e] (update e :counter inc))
  (define-effect Log [&] (set updated true))
  (defn log-increase [max-counter]
    (make-spy
      (fn [_ oe]
        (make-snoop
          @{:snoop (fn [self ne spys event]
                     (when (>= (ne :counter) max-counter)
                       (array/clear spys)
                       Log))}))
      "log-increase-max-2"))
  (:transact manager Zero (log-increase 2) Increment Increment)
  updated)

(assert-with-manager
  "define-spy"
  (var updated false)
  (define-update Zero [_ e] (put e :counter 0))
  (define-update Increment [_ e] (update e :counter inc))
  (define-effect Log [&] (set updated true))
  (define-spy LogIncrease [_ oe]
    (make-snoop
      @{:old-counter (oe :counter)
        :snoop (fn [self ne spys event]
                 (when (> (ne :counter) (self :old-counter))
                   (set (self :old-counter) (ne :counter))
                   (array/clear spys)
                   Log))}))
  (:transact manager Zero LogIncrease Increment)
  updated)
(end-suite)
