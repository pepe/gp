# This is the simplest example, we use only manager core and event modules
(use /gp/events)

(def manager
  "New initialized manager"
  (make-manager @{:counter 0}))

(define-event IncreaseCounter
  "Static Event with only :update method, that increases the counter"
  @{:update (fn [_ state] (update state :counter inc))})

(define-event PrintCounter
  "Static Event with only :print method, that prints the counter"
  @{:effect (fn [_ state _]
              (print "Counter is: " (state :counter)))})

(def inc-and-print
  "Dynamic Event with only :watch mothod, that combines increasing and printing"
  (make-event @{:watch (fn [_ _ _] [IncreaseCounter PrintCounter])}))

# We confirm the combined Event
(:transact manager inc-and-print)
# => Counter is: 1

# We confirm increasing ten times
(:transact manager ;(seq [_ :range [0 10]] IncreaseCounter))

# and print the counter
(:transact manager PrintCounter)
# => Counter is: 11

