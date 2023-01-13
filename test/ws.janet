(use spork/test spork/misc)
(import ../gp/net/server)
(use ../gp/net/ws)
(start-suite "Documentation")
(assert-docs "../gp/net/ws")
(end-suite)
(start-suite "Response")

(assert (= (string (response 0xA "Pong"))
           "\x8A\x04Pong")
        "response")

(assert (= (string (text "Hey")) "\x81\x03Hey")
        "text")

(assert (= (string (binary "Hey")) "\x82\x03Hey")
        "binary")

(end-suite)

# TODO add server and so on
(start-suite "Supervisor on-connection")

(end-suite)
