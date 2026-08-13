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

# Re-opening a client that still holds a line lets the old one go. It used
# to overwrite the stream and say nothing, which sends no close: the peer's
# fiber stayed parked on a socket nobody would speak on again, and this
# side kept the descriptor until the collector reached it. Cheap once, and
# a registration renewed on a beat does it every minute.
(let [old (test-client :stream)]
  (assert (:open test-client) "open a client that already has a line")
  (assert (not= old (test-client :stream)) "and it holds a new one")
  (assert (match (protect (:write old "x"))
            [false _] true
            false)
          "while the line it let go of is closed"))
(assert (= (:hello test-client) "hello") "and still answers on the new one")

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
