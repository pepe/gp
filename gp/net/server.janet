(import ../events)

(defmacro supervisor
  ```
  Simple supervisor with handling new connection.
  And closing the connection.

  A rule that raises does not end the supervision. This loop is the only
  reader of the server's channel, so a supervisor that dies of handling
  one failure leaves a listener open with nobody behind it, and every
  connection accepted from then on waits for an answer that cannot come.
  The failure is reported and the next message taken.

  The message is taken outside that guard, and a closed channel ends the
  supervision. Closing is how a server says it has nothing more to hand
  over; taking from it after that yields nil without ever waiting, and a
  loop that kept matching on nil would spin the event loop flat.
  ```
  [chan handling & rules]
  (assert (even? (length rules)) "Rules must be pairs")
  (def default-rules
    ~[,;rules
      # Whoever asks for a connection to be closed rarely knows whether it
      # still is one, and a supervisor must not fall over being told twice.
      [:close connection] (protect (:close connection))
      [:conn connection]
      (ev/go
        (fiber/new
          (fn handling-connection [conn]
            (setdyn :conn conn)
            (,handling conn)) :tp) connection ,chan)])
  (with-syms [message]
    ~(forever
       (def ,message (ev/take ,chan))
       (if (nil? ,message) (break))
       (try
         (match ,message ,;default-rules)
         ([err fib]
           (eprint "Supervisor rule failed: " err)
           (when (dyn :debug) (debug/stacktrace fib err)))))))

(defn start
  ```
  This function starts the server. Usually in the fiber.
  
  It takes channel to which it will put incomming connection under tag `:conn`.

  It takes two optional arguments:
  - `host` on which server starts. Default `localhost`
  - `port` on which server starts. Default `8888`
  ```
  [chan &opt host port]
  (default host "localhost")
  (default port "8888")
  (def listener (net/listen host port))
  [(ev/go
     (fn accept-connection [server]
       (forever
         # A closed listener accepts nil, not an error. Handing that on as
         # though it were a connection is how a server that is shut down
         # takes its supervisor with it.
         (if-let [connection (net/accept server)]
           (ev/give-supervisor :conn connection)
           (break))))
     listener chan) listener])

(defmacro spawn
  ```
  Spawns new server with handling, host port and rules.
  
  It takes two required parameters:
  - `supervisor` supervisor macro you want to use, usually one of specialized for http, ws
    or rpc.
  - `handling` handling function, usually composed by specific `on-connection` function
    and handler function or object.
  
  It also takes three optional parameters:
  - `host` hostname to bind to.
  - `port` port to bind to.
  - `rules` variadic rules' pairs for the supervisor pattern matching.
  
  It returs the supervisor channel.
  ```
  [svisor handling &opt host port & rules]
  (with-syms [chan h]
    ~(let [,chan (ev/chan)]
       (ev/spawn
         (,start ,chan ,host ,port)
         (as-macro ,svisor ,chan ,handling ,;rules))
       ,chan)))

(defn host-port
  "Splits connection string into host and port parts."
  [conns]
  (string/split ":" conns))
