# We will use event, events and cocoons modules heavily
(use /gp/events)

# Static update event for setting :amount in the state to zero
(define-update ZeroAmount [_ state]
  (put state :amount 0))

# Dynamic update event that increases :amount in the state by given amount.
(defn increase-amount [amount]
  (make-update
    (fn [_ state]
      (update state :amount |(+ amount $)))
    (string "increase amount by " amount)))

# Dynamic update event that decreases :amount in the state by given amount.
(defn decrease-amount [amount]
  (make-update
    (fn [_ state]
      (update state :amount |(- amount $)))
    (string "decrease amount by " amount)))

# Static watch event that sets up the initial :amount in the state.
(define-watch PrepareState [&]
  [ZeroAmount (increase-amount 1)])

# Static spy event which prints the value if it is updated to more than one milion
# and removes all spys
(define-spy BigAmountAlarm [_ e]
  (make-snoop
    @{:snoop
      (fn [_ {:amount amount} snoops]
        # Check the :amount
        (when (> amount 1_000_000)
          # If hi enough, remove all snoops and print message
          (array/clear snoops)
          (make-effect
            (fn [&] (print "Oh yes! Amount is hi at: " amount)))))}))

# Static event that logs the hard computing ahead
(define-effect HardWork [&]
  (print "Hard computing"))

# Static events that returns the Cocoon with eventual work
(define-watch AddRandom [&]
  # Give the Cocoon to the Shawn
  (producer
    # Emerge log event to the Shawn
    (produce HardWork)
    # Do the computing
    (var res 0)
    (loop [_ :range [0 1_000_000]]
      (+= res (math/random)))
    # Emarge increase event to the Shawn with computed amount
    (produce (increase-amount res))))

# Dynamic event that returns i times AddRandom event
(defn add-many-randoms [i]
  (make-watch (fn [&] (seq [_ :range [0 i]] AddRandom))))

# Static event that return the thread Cocoon with eventual work
(define-watch ThreadRandom [_ state _]
  # Give the Thread Cocoon to the Shawn
  (thread-producer
    # Emerge log event to the Shawn
    (produce HardWork)
    # Do the computing
    (var res 0)
    (loop [_ :range [0 1_000_000]]
      (+= res (math/random)))
    # Emarge increase event to the Shawn with computed amount
    (produce (increase-amount res))))

# Dynamic event that returns i times ThreadRandom event
(defn add-many-trandoms [amount]
  (make-watch (fn [&] (seq [_ :range [0 amount]] ThreadRandom))))

# Static event that prints the state
(define-effect PrintState [_ state _]
  (prin "State: ") (pp state))

# Static event that prints the help message
(define-effect PrintHelp [&]
  (print
    ```
    Available commands:
      0 make amount zero
      + [num] add 1 or num to amount
      - [num] substrevent 1 or num from amount
      r [num] compute and add 1 or num random numbers to amount
      t [num] compute and add 1 or num random numbers to amount in threads
      p print state
      h print this help
      q quit console
    ```))

# Dynamic event that prints the warning about unknown command
# and help message
(defn unknown-command [command]
  (make-event {:watch (fn [&] PrintHelp)
               :effect (fn [&] (print "Unknown command: " command))}))

# Static event that exits the application
(define-effect Exit [&]
  (print "Bye!") (os/exit))
