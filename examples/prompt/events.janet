# We will use event, events and cocoons modules heavily
(use /gp/events)

# Static UpdateAct for setting :amount in the envelope to zero
(define-update ZeroAmount [_ envelope]
  (put envelope :amount 0))

# Dynamic UpdateAct that increases :amount in the envelope by given amount.
(defn increase-amount [amount]
  (make-update
    (fn [_ envelope]
      (update envelope :amount |(+ amount $)))
    (string "increase amount by " amount)))

# Dynamic UpdateAct that decreases :amount in the envelope by given amount.
(defn decrease-amount [amount]
  (make-update
    (fn [_ envelope]
      (update envelope :amount |(- amount $)))
    (string "decrease amount by " amount)))

# Static WatchAct that sets up the initial :amount in the envelope.
(define-watch PrepareEnvelope [&]
  [ZeroAmount (increase-amount 1)])

# Static SpyAct which prints the value if it is updated to more than one milion
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
            (fn [&] (print "Oh yes! Amount is hi at: " amount))) ))}))

# Static Act that logs the hard computing ahead
(define-effect HardWork [&]
  (print "Hard computing"))

# Static events that returns the Cocoon with eventual work
(define-watch AddRandom [&]
  # Give the Cocoon to the Shawn
  (producer
    # Emerge log Act to the Shawn
    (produce HardWork)
    # Do the computing
    (var res 0)
    (loop [_ :range [0 1_000_000]]
      (+= res (math/random)))
    # Emarge increase Act to the Shawn with computed amount
    (produce (increase-amount res))))

# Dynamic Act that returns i times AddRandom Act
(defn add-many-randoms [i]
  (make-watch (fn [&] (seq [_ :range [0 i]] AddRandom))))

# Static Act that return the thread Cocoon with eventual work
(define-watch ThreadRandom [_ envelope _]
  # Give the Thread Cocoon to the Shawn
  (thread-producer
    # Emerge log Act to the Shawn
    (produce HardWork)
    # Do the computing
    (var res 0)
    (loop [_ :range [0 1_000_000]]
      (+= res (math/random)))
    # Emarge increase Act to the Shawn with computed amount
    (produce (increase-amount res))))

# Dynamic Act that returns i times ThreadRandom Act
(defn add-many-trandoms [amount]
  (make-watch (fn [&] (seq [_ :range [0 amount]] ThreadRandom))))

# Static Act that prints the envelope
(define-effect PrintEnvelope [_ envelope _]
  (prin "Envelope: ") (pp envelope))

# Static Act that prints the help message
(define-effect PrintHelp [&]
  (print
    ```
    Available commands:
      0 make amount zero
      + [num] add 1 or num to amount
      - [num] substrevent 1 or num from amount
      r [num] compute and add 1 or num random numbers to amount
      t [num] compute and add 1 or num random numbers to amount in threads
      p print envelope
      h print this help
      q quit console
    ```))

# Dynamic Act that prints the warning about unknown command
# and help message
(defn unknown-command [command]
  (make-event {:watch (fn [&] PrintHelp)
             :effect (fn [&] (print "Unknown command: " command))}))

# Static Act that exits the application
(define-effect Exit [&]
  (print "Bye!") (os/exit))
