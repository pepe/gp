(use spork/test spork/misc)
(import ../gp/net/server)
(use ../gp/net/rpc)

(start-suite "RPC documentation")
(assert-docs "../gp/net/rpc")
(end-suite)

(start-suite "Supervisor on-connection")

(def psk "helohelohelohelohelohelohelohelo")
(def handler
  @{:hello (fn hello [_] "hello")
    :psk psk
    :die (fn die [self] (os/exit))})

(ev/spawn
  (def sc (ev/chan))
  (def handling (on-connection handler))
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

(:die test-client)

(end-suite)
(start-suite "Server")
(assert (= :core/channel
           (type (server handler "localhost" 9998)))
        "returns channel")
(ev/sleep 0.001) # give server time to settle
(set test-client
     (client "localhost" 9998 "pepe" psk))
(assert
  (= (:hello test-client) "hello")
  "hello fn")
(:die test-client)
(end-suite)
