(use spork/test spork/misc)
(import ../gp/net/server)
(use ../gp/net/rpc)

(start-suite "RPC documentation")
(assert-docs "../gp/net/rpc")
(end-suite)

(def psk "helohelohelohelohelohelohelohelo")

(start-suite "on-connection")
(assert (function? (on-connection @{:hello (fn hello [_] "hello")
                                    :psk psk}))
        "on-connection function")
(assert (match (protect (on-connection {}))
          [false "Handler is not valid"] true
          false) "wrong type handler")
(assert (match (protect (on-connection @{}))
          [false "Handler is not valid"] true
          false) "empty handler")
(end-suite)

(start-suite "Supervisor on-connection")
(ev/spawn
  (def sc (ev/chan))
  (def handling (on-connection @{:hello (fn hello [_] "hello")
                                 :psk psk}))
  (server/start sc "localhost" 9999)
  (supervisor sc handling))

(ev/sleep 0.001) # give server time to settle

(var test-client
  (client "localhost" 9999 "pepe" psk))

(assert test-client "client created")

(assert
  (= (:hello test-client) "hello")
  "hello fn")

(assert-error
  "not supported fn"
  (:bye test-client))

(assert
  (:close test-client)
  "close test-client")

(assert-error
  "already closed test-client"
  (:hello test-client))

(assert
  (:reopen test-client)
  "reopen test-client")

(assert-error
  "bad psk"
  (client
    "localhost"
    9999 "pepe"
    "badybadybadybadybadybadybadybady"))
(end-suite)

(start-suite "Server")
(assert (= :core/channel
           (type (server @{:hello (fn hello [_] "hello") :psk psk}
                         "localhost" 9998)))
        "returns channel")
(ev/sleep 0.001) # give server time to settle
(def test-client
  (client "localhost" 9998 "pepes" psk))
(assert
  (= (:hello test-client) "hello")
  "hello fn")
(end-suite)
(os/exit)
