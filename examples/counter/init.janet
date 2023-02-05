# This is the simplest example, we use only shawn core and act modules
(use /shawn /shawn/act)

# shawn initialization
(def shawn (initialize @{:counter 0}))

# Static Act with only :update method, that increases the counter
(define-act IncreaseCounter
  @{:update (fn [_ state] (update state :counter inc))})

# Static Act with only :print method, that prints the counter
(define-act PrintCounter
  @{:effect (fn [_ state _]
              (print "Counter is: " (state :counter)))})

# Dynamic Act with only :watch mothod, that combines increasing and printing
(def inc-and-print
  (make-act @{:watch (fn [_ _ _] [IncreaseCounter PrintCounter])}))

# We confirm the combined Act
(:confirm shawn inc-and-print)
# => Counter is: 1

# We confirm increasing ten times
(:confirm shawn ;(seq [_ :range [0 10]] IncreaseCounter) )
# and print the counter
(:confirm shawn PrintCounter)
# => Counter is: 11
