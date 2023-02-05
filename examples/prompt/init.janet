# Example of the prompt based CLI application
# driven by the shawn
(import /shawn)
# PEG based parser of the commands
(import /examples/prompt/parser)
# Acts definining the flow in the application
(import /examples/prompt/acts)

# Here we initialize shawn with empty table
(def shawn (shawn/initialize @{}))
# and confirm the act which setups the initial state
(:confirm shawn acts/PrepareEnvelope acts/BigAmountAlarm)

# Main loop of the application
(forever
  # Read the input from command line
  (def readout (-> "Command [+ - 0 r t p q h]: " getline string/trim))
  # Parse it for a command
  (def cmd
    (match (parser/parse-command readout)
      [:inc amount] (acts/increase-amount amount)
      [:dec amount] (acts/decrease-amount amount)
      [:zero] acts/ZeroAmount
      [:rnd amount] (acts/add-many-randoms amount)
      [:trnd amount] (acts/add-many-trandoms amount)
      [:print] acts/PrintEnvelope
      [:help] acts/PrintHelp
      [:exit] acts/Exit
      nil (acts/unknown-command readout)))
  # Confirm Act for the command or unknown-command Act
  (:confirm shawn cmd)
  # Wait for shawn to finish all the processing
  (:admit shawn))
