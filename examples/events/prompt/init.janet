# Example of the prompt based CLI application
# driven by the manager
(use /gp/events)
# PEG based parser of the commands


(def grammar
  "Commands grammar"
  (peg/compile
    ~{:spc " "
      :num (cmt (<- (some (range "09")) :num) ,scan-number)
      :inc (* "+" -1 (constant :inc) (constant 1))
      :dec (* "-" -1 (constant :dec) (constant 1))
      :pinc (* "+" :spc (constant :inc) :num)
      :pdec (* "-" :spc (constant :dec) :num)
      :zero (* "0" -1 (constant :zero))
      :rnd (* "r" (+ (* -1 (constant :rnd) (constant 1))
                     (* :spc (constant :rnd) :num)))
      :print (* "p" -1 (constant :print))
      :help (* "h" -1 (constant :help))
      :exit (* "q" -1 (constant :exit))
      :main (+ :inc
               :dec
               :pinc
               :pdec
               :zero
               :rnd
               :print
               :print
               :help
               :exit)}))

(defn parse-command
  "Parses the command from `s`"
  [s]
  (peg/match grammar s))

# events definining the flow in the application
(use /gp/events)

(define-update ZeroAmount
  "Static update event for setting :amount in the state to zero"
  [_ state]
  (put state :amount 0))

(defn increase-amount
  "Dynamic update event that increases :amount in the state by given amount."
  [amount]
  (make-update
    (fn [_ state]
      (update state :amount |(+ amount $)))
    (string "increase amount by " amount)))

(defn decrease-amount
  "Dynamic update event that decreases :amount in the state by given amount."
  [amount]
  (make-update
    (fn [_ state]
      (update state :amount |(- amount $)))
    (string "decrease amount by " amount)))

(define-watch PrepareState
  "Static watch event that sets up the initial :amount in the state."
  [&]
  [ZeroAmount (increase-amount 1)])

(define-effect HardWork
  "Static event that logs the hard computing ahead"
  [&]
  (print "Hard computing"))

(define-watch AddRandom
  "Static events that returns the Producer with eventual work"
  [&]
  (producer
    # Produce log event to the Manager
    (produce HardWork)
    # Do the computing
    (var res 0)
    (loop [_ :range [0 1_000_000]]
      (+= res (math/random)))
    # Produce increase event to the Manager with computed amount
    (produce (increase-amount res))))

(defn add-many-randoms
  "Dynamic event that returns i times AddRandom event"
  [i]
  (make-watch (fn [&] (seq [_ :range [0 i]] AddRandom))))

(define-effect PrintState
  "Static event that prints the state"
  [_ state _]
  (prin "State: ") (pp state))

(define-effect PrintHelp
  "Static event that prints the help message"
  [&]
  (print
    ```
    Available commands:
      0 make amount zero
      + [num] add 1 or num to amount
      - [num] substrevent 1 or num from amount
      r [num] compute and add 1 or num random numbers to amount
      p print state
      h print this help
      q quit console
    ```))


(defn unknown-command
  "Dynamic event that prints the warning about unknown command and help message"
  [command]
  (make-event {:watch (fn [&] PrintHelp)
               :effect (fn [&] (print "Unknown command: " command))}))

(define-effect Exit
  "Static event that exits the application"
  [&]
  (print "Bye!") (os/exit))

(define-watch Prompt
  "Producer which loops on reading the command and producing events"
  [&]
  (producer
    (forever
      # Read the input from command line
      (def readout (-> "Command [+ - 0 r p q h]: " getline string/trim))
      # Parse it for a command
      (def cmd
        (match (parse-command readout)
          [:inc amount] (increase-amount amount)
          [:dec amount] (decrease-amount amount)
          [:zero] ZeroAmount
          [:rnd amount] (add-many-randoms amount)
          [:print] PrintState
          [:help] PrintHelp
          [:exit] Exit
          nil (unknown-command readout)))
      (produce cmd)
      (ev/sleep 0))))

(def manager
  "New initialized manager"
  (make-manager @{}))

#  transact the event which setups the initial state
(:transact manager PrepareState Prompt)

# Confirm envet for the command or unknown-command Act
# Wait for manager to finish all the processing
(:await manager)
