# This is the simplest example, we use only shawn core and event modules
(use /gp/events)

# shawn initialization
(def shawn (make-manager @{:counter 0}))

# Static Act with only :update method, that increases the counter
(define-event IncreaseCounter
  @{:update (fn [_ state] (update state :counter inc))})

# Static Act with only :print method, that prints the counter
(define-event PrintCounter
  @{:effect (fn [_ state _]
              (print "Counter is: " (state :counter)))})

# Dynamic Act with only :watch mothod, that combines increasing and printing
(def inc-and-print
  (make-event @{:watch (fn [_ _ _] [IncreaseCounter PrintCounter])}))

# We confirm the combined Act
(:transact shawn inc-and-print)
# => Counter is: 1

# We confirm increasing ten times
(:transact shawn ;(seq [_ :range [0 10]] IncreaseCounter) )
# and print the counter
(:transact shawn PrintCounter)
# => Counter is: 11
