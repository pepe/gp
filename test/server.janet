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
