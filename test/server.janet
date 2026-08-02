(use spork/test spork/misc)
(use ../gp/net/server)
(start-suite "Server documentation")
(assert-docs "../gp/net/server")
(end-suite)

(def c (ev/chan))
(start-suite "supervisor")
(assert
  (= ((compile '(supervisor (ev/chan) identity [:error])) :error)
     "(macro) Rules must be pairs")
  "wrong rules")
(end-suite)

(start-suite "supervisor survives a failing rule")
# A supervisor is the only reader of its server's channel. One that dies
# of handling a failure leaves a listener open with nobody behind it, so
# a raising rule must cost the message and nothing more.
(def sc (ev/chan))
(var supervising true)
(var seen nil)
(ev/go
  (fn []
    (defer (set supervising false)
      (supervisor sc identity
                  [:boom _] (error "rule blew up")
                  [:mark m] (set seen m)))))
(ev/give sc [:boom true])
(ev/sleep 0.05)
(assert supervising "supervision outlives a raising rule")
(ev/give sc [:mark :after])
(ev/sleep 0.05)
(assert (= seen :after) "later messages are still supervised")
(ev/chan-close sc)
(ev/sleep 0.05)
(assert (not supervising) "a closed channel ends the supervision")
(end-suite)

(start-suite "start")
(var res nil)
(ev/spawn (start c "localhost" 8000))
(ev/sleep 0.001)

(def w (net/connect "localhost" 8000))
(net/write w "HOHO")
(ev/sleep 0.001)

(let [[_ conn] (ev/take c)] (set res (net/read conn 4)))
(net/close w)
(assert (deep= res @"HOHO") "read written")
(end-suite)
(ev/chan-close c)
(os/exit)
