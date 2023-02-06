# Example of the prompt based CLI application
# driven by the shawn
(use /gp/events)
# PEG based parser of the commands
(import /examples/events/prompt/parser)
# events definining the flow in the application
(import /examples/events/prompt/events)

# Here we initialize shawn with empty table
(def shawn (make-manager @{}))
# and transact the event which setups the initial state
(:transact shawn events/PrepareState events/BigAmountAlarm)

# Main loop of the application
(forever
  # Read the input from command line
  (def readout (-> "Command [+ - 0 r t p q h]: " getline string/trim))
  # Parse it for a command
  (def cmd
    (match (parser/parse-command readout)
      [:inc amount] (events/increase-amount amount)
      [:dec amount] (events/decrease-amount amount)
      [:zero] events/ZeroAmount
      [:rnd amount] (events/add-many-randoms amount)
      [:trnd amount] (events/add-many-trandoms amount)
      [:print] events/PrintState
      [:help] events/PrintHelp
      [:exit] events/Exit
      nil (events/unknown-command readout)))
  # Confirm envet for the command or unknown-command Act
  (:transact shawn cmd)
  # Wait for shawn to finish all the processing
  (:await shawn))
