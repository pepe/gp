(import ../events)
(import ./socket :as unix-socket)

(defn host-port
  ```
  Parses a TCP `host:port` or `unix:/absolute/path` endpoint.
  A Unix endpoint becomes [:unix path], accepted by net/listen and net/connect.
  ```
  [address]
  (assert (string? address) "An endpoint must be a string")
  (if (string/has-prefix? "unix:" address)
    (let [path (slice address 5)]
      (assert (unix-socket/path? path) "Invalid Unix socket path")
      [:unix path])
    (let [parts (string/split ":" address)]
      (def [host port] parts)
      (assert (and (= 2 (length parts)) (not (empty? host))
                   (peg/match '(* (some :d) -1) port)
                   (<= 0 (scan-number port) 65535))
              "Invalid TCP endpoint")
      [host port])))

(defn address?
  "Whether `address` is a valid TCP or filesystem Unix socket endpoint."
  [address]
  (first (protect (host-port address))))

(defn address
  "Renders the canonical endpoint of a client without losing its transport."
  [{:host host :port port}]
  (string (if (= :unix host) "unix" host) ":" port))

(defn close
  "Closes a server listener, including Unix pathname cleanup and claim release."
  [listener]
  (unix-socket/close listener))

(defn close-all
  "Releases Unix listeners owned by this process before its graceful exit."
  []
  (unix-socket/close-all))

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
  For a Unix socket, host is :unix and port is its absolute filesystem path.
  Close the returned listener with server/close, not only net/close.
  `socket-mode` is optional 0600/0660, used only for Unix sockets.
  ```
  [chan &opt host port socket-mode]
  (default host "localhost")
  (default port "8888")
  (def listener (if (= :unix host)
                  (unix-socket/listen port socket-mode)
                  (net/listen host port)))
  [(ev/go
     (fn accept-connection [server]
       (defer (close server)
        (forever
         # A closed listener normally accepts nil. If it was closed before
         # this task first runs, accept instead raises "stream is closed".
         # Neither is a connection worth handing to the server supervisor;
         # any other accept error still is.
         (def [open? connection] (protect (net/accept server)))
         (if open?
           (if connection
             (ev/give-supervisor :conn connection)
             (break))
           (if (= connection "stream is closed")
             (break)
             (error connection))))))
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
