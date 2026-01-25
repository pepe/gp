(import spork/misc :prefix "" :export true)
(import spork/json :export true)
(import spork/netrepl :export true)
(import spork/temple :export true)
(import spork/htmlgen :as hg :export true)
(import spork/path :export true)
(import spork/mdz :export true)
(import spork/sh :export true)
(import jhydro :prefix "" :export true)

(import ../route :export true)
(import ../utils :prefix "" :export true)
(import ../data :prefix "" :export true)
(import ../events :prefix "" :export true)
(import ../datetime :as dt :export true)
(import ../net/server :export true)
(import ../net/http :export true)
(import ../net/rpc :export true)
(import gp/data/fuzzy :export true)

(defn log
  "Create logging event from the message `msg`."
  [& msg]
  (make-effect (fn log [_ state _]
                 (if (state :log) (eprint ;msg))) "log"))

(defn logr
  "Create logging event from the message `msg`."
  [& msg]
  (make-effect (fn log [_ state _]
                 (if (state :debug) (eprint ;msg))) "log"))

(defn logf
  "Create logging formating event from the `format` and the message `msg`."
  [format & msg]
  (make-effect (fn log [_ state _]
                 (if (state :log)
                   (eprintf format ;msg))) "logf"))

(defn event-journal
  "Middleware that produces log of the request."
  [next-middleware]
  (http/journal
    next-middleware
    |(produce
       (logf "%s %s %s in %s, %s"
             ($ :head) ($ :method) ($ :fulluri)
             ($ :elapsed) ($ :reqs)))))

(defn stacktrace
  "Create stacktrace event from the fiber `fib`."
  [fib]
  (make-effect
    (fn stacktrace [_ state _]
      (if (state :debug) (debug/stacktrace fib))) "stacktrace"))
