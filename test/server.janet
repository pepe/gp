(use spork/test spork/misc)
(use ../gp/process/server)
(start-suite "Server documentation")
(assert-docs "../gp/process/server")
(end-suite)

(start-suite "Server")
(var res nil)

(def c (ev/chan))
(ev/call start c "localhost" 8000)
(ev/sleep 0.001)

(def w (net/connect "localhost" 8000))
(net/write w "HOHO")
(ev/sleep 0.001)

(let [[_ conn] (ev/take c)] (set res (net/read conn 4)))
(net/close w)
(ev/chan-close c)
(assert (deep= res @"HOHO") "read written")
(os/exit)
(end-suite)
