# Here we are using the vanila spork RPC client
(import spork/rpc)

# Connect two clients
(def pupa1 (rpc/client "localhost" "9999"))
(def pupa2 (rpc/client "localhost" "9998"))

# RPC calls
(:inc pupa1)
(:inc pupa1)
(:inc pupa1)
(:inc pupa1)
(prin "First pupa ")
# Print the returned value of the envelope
(pp (:print pupa1))
# Stop the first server
(:die pupa1)
# RPC calls
(:inc pupa2)
(prin "Second pupa ")
# Print the returned value of the envelope
(pp (:print pupa2))
# Stop the second server
(:die pupa2)
