(use spork/misc spork/zip jhydro)

(use ../data/schema)
(import ./server)
(import ./socket)
###
### hydrpc.janet
###
### Crypto RPC server and client tailored to Janet.
###
### Parts blatantly stolen from janet-lang/spork/rpc

### Limitations: ????
###
### Currently calls are resolved in the order that they are sent
### on the connection - in other words, a single RPC server must resolve
### remote calls sequentially. This means it is recommended to make multiple
### connections for separate transactions.

(use spork/msg)

(def ctx "Dynamic context for hydro" (dyn :ctx "gprpcctx"))

(defn- make-encoder
  [get-msg-id session-pair]
  (fn encoder [msg]
    (-> msg
        marshal
        compress
        (secretbox/encrypt (get-msg-id) ctx (session-pair :tx)))))

(defn- make-decoder
  [get-msg-id session-pair]
  (fn decoder [msg]
    (-> msg
        (secretbox/decrypt (get-msg-id) ctx (session-pair :rx))
        decompress
        unmarshal)))

(defmacro supervisor
  ```
  Default supervisor.
  Param chan is the supervising channel of the server,
  handling is the handling object.
  ```
  [chan handling & rules]
  (def additional-rules
    ~[[:error fiber]
      (do
        (def err (fiber/last-value fiber))
        # A fiber can fail with no connection to answer on: the fiber
        # accepting on the address does exactly that when the server is
        # closed under it. Only a failure with someone waiting is closable.
        (def conn (get (fiber/getenv fiber) :conn))
        (eprint err)
        # And what stands under :conn need not be a connection any more:
        # the env a failed fiber inherited outlives the connection that
        # last wrote to it.
        (when conn (protect (:close conn))))
      ,;rules])
  ~(as-macro ,server/supervisor ,chan ,handling ,;additional-rules))

(defn- key/admits
  ```
  A predicate admitting the public keys `allowed` names -- an indexed
  collection of them, or a predicate of its own -- and every key when it
  names none.
  ```
  [allowed]
  (cond
    (nil? allowed) (fn [_] true)
    (or (function? allowed) (cfunction? allowed)) allowed
    (let [admitted (tabseq [k :in allowed] (string k) true)]
      (fn [pk] (truthy? (admitted (string pk)))))))

(def- settings
  "What a handler holds for the server itself, and never offers as a method."
  {:psk true :keypair true :allowed true})

(defn on-connection
  ```
  Create a handler for the RPC server. It must take a dictionary of handler
  with methods that clients can call. Under the :psk must be the preshared key
  for the jhydro handler.

  Under `:keypair` may be the server's own static `kx/keygen` keypair, by
  which its clients know it; without one, a new one is made. Under
  `:allowed` may be the public keys of the clients it admits, as an indexed
  collection or a predicate; without it, whoever knows the psk is admitted.
  With both, the psk is no secret: the keys are. None of the three is ever
  one of the methods.

  The handler is left as it was given. `server` makes a handling of it
  for every connection, and a handler emptied of its psk by the first
  would have met the second without one -- and without the keys it
  admits, admitting anyone.
  This function can be used by the `net/server`.
  ```
  [handler]
  (assert ((??? table? present?) handler) "Handler is not valid")
  (def psk (handler :psk))
  (def {:public-key pk :secret-key sk} (or (handler :keypair) (kx/keygen)))
  (def admitted? (key/admits (handler :allowed)))
  (def keys-msg (freeze (filter |(not (settings $)) (keys handler))))
  (def known-peers @{})

  (fn on-connection [connection]
    (defn handshake []
      (def hrecv (make-recv connection identity))
      (def hsend (make-send connection identity))
      (var packet1 (hrecv))
      (if-let [[peer-pk _] (known-peers (string packet1))]
        (do
          # Known by an earlier handshake, and back again: a key taken
          # off the list must not come in by the short way.
          (assert (admitted? peer-pk) "The peer's key is not admitted")
          (set packet1 (hrecv))
          (def packet2 (buffer/new 48))
          (def ret [(kx/kk2 packet2 packet1 peer-pk pk sk) peer-pk])
          (hsend packet2)
          ret)
        (do
          (def packet2 (buffer/new 96))
          (def state (kx/xx2 packet2 packet1 psk pk sk))
          (hsend packet2)
          (def packet3 (hrecv))
          (def peer-pk (buffer/new 32))
          (def session-pair (kx/xx4 state packet3 psk peer-pk))
          (assert (admitted? peer-pk) "The peer's key is not admitted")
          [session-pair peer-pk])))
    (try
      (let [[session-pair peer-pk] (handshake)]
        (var msg-id 0)
        (def recv (make-recv connection (make-decoder (fn [] msg-id) session-pair)))
        (def send (make-send connection (make-encoder (fn [] msg-id) session-pair)))
        (def peer-name (recv))
        (put known-peers peer-name [peer-pk (os/time)])
        (send keys-msg)
        (forever
          (let [msg (recv)
                [fnname args] msg
                f (unless (settings fnname) (handler fnname))]
            (++ msg-id)
            (if f
              (send (protect (f handler ;args)))
              (send [false (string "no function " fnname " supported")])))))
      ([_] (ev/give-supervisor :close connection)))))

(defmacro server
  ```
  Convenience for spawning rpc server with default `supervisor`.
  
  It has one parameter `handler` with the object, that handles the requests.
  
    It also takes three optional parameters:
  - `host` hostname to bind to.
  - `port` port to bind to.
  - `rules` variadic rules' pairs for the supervisor pattern matching.
  ```
  [handler &opt host port & rules]
  ~(as-macro ,server/spawn ,supervisor (,on-connection ,handler)
             ,host ,port ,;rules))

(defn- with-client-lock
  "Serializes calls and connection setup on one client, including their waits."
  [self body]
  (def gate (or (self :rpc-lock)
                (let [gate (ev/chan 1)]
                  (ev/give gate true)
                  (put self :rpc-lock gate)
                  gate)))
  (ev/with-deadline (get self :timeout 8)
    (ev/take gate)
    (defer (ev/give gate true) (body))))

(defn- discard-stream
  "Closes a failed generation without clearing a newer connection."
  [self stream]
  (when (= stream (self :stream)) (put self :stream nil))
  (when stream (protect (:close stream))))

(def Client
  ```
  Prototype for the RPC client.
  TODO: document
  ```
  @{# Opening a client that already holds a line replaces it, and letting
    # go of the old one is the whole of the difference. Overwriting the
    # stream and saying nothing left a connection open at both ends with
    # nobody on this side holding it: no close is sent, so the peer's
    # accepting fiber stays parked on a socket that will never speak
    # again, and this side only lets the descriptor go whenever the
    # collector happens to reach it. One dropped line per re-open sounds
    # like nothing until something re-opens on a beat -- a registration
    # renewed every minute is sixty of them an hour, each with a fiber
    # waiting on the other end.
    :open (fn open [self]
            (with-client-lock self
              (fn []
                (discard-stream self (self :stream))
                (def stream (socket/connect (self :host) (self :port)))
                (set (self :stream) stream)
                (var ready false)
                (defer (unless ready (discard-stream self stream))
                  (merge-into self (or (self :keypair) (kx/keygen)))
                  (:handshake self)
                  (:setup-connection self)
                  (set ready true)
                  self))))
    :close (fn close [self]
             # Closing must interrupt a parked call, not wait for its lock.
             (discard-stream self (self :stream))
             self)
    :reopen
    (fn reopen [self]
      (with-client-lock self
        (fn []
          # A failed line is still a descriptor until it is closed.
          (discard-stream self (self :stream))
          (def stream (socket/connect (self :host) (self :port)))
          (set (self :stream) stream)
          (var ready false)
          (defer (unless ready (discard-stream self stream))
            (def hrecv (make-recv stream string))
            (def hsend (make-send stream string))
            (hsend (self :name))
            (def packet1 (buffer/new 48))
            (def state (kx/kk1 packet1 (self :peer-pk)
                               (self :public-key) (self :secret-key)))
            (hsend packet1)
            (def packet2 (hrecv))
            (set (self :session-pair)
                 (kx/kk3 state packet2 (self :public-key) (self :secret-key)))
            (:setup-connection self)
            (set ready true)
            self))))
    :handshake
    (fn handshake [self]
      (def {:public-key pk :secret-key sk} self)
      (def hrecv (make-recv (self :stream) string))
      (def hsend (make-send (self :stream) string))
      (def packet1 (buffer/new 48))
      (def state (kx/xx1 packet1 (self :psk)))
      (hsend packet1)
      (def packet2 (hrecv))
      (def packet3 (buffer/new 64))
      (def peer-pk (buffer/new 32))
      (set (self :session-pair)
           (kx/xx3 state packet3 packet2 (self :psk) pk sk peer-pk))
      # A server known by its key is left before the last packet: no
      # session is finished with one that is not it.
      (when-let [expected (self :server-key)]
        (assert (= (string expected) (string peer-pk))
                "The server's key is not the one expected"))
      (set (self :peer-pk) peer-pk)
      (hsend packet3))
    :setup-connection
    (fn setup-connection [self]
      (def stream (self :stream))
      (var msg-id 0)
      (def recv
        (make-recv (self :stream) (make-decoder (fn [] msg-id) (self :session-pair))))
      (def send
        (make-send (self :stream) (make-encoder (fn [] msg-id) (self :session-pair))))
      # A server that does not admit a key finishes the handshake first, and
      # only then lets the line go. The refusal is what comes of the first
      # exchange: nothing read on one system, a broken line on another.
      (def [answered fnames] (protect (send (self :name)) (recv)))
      (assert (and answered fnames)
              "The server closed the line unanswered: it may not admit this key")
      (each f fnames
        (set (self (keyword f))
             (fn rpc-function [_ & args]
               (with-client-lock self
                 (fn []
                   # A queued closure can belong to a connection replaced
                   # while it waited. Never send it on the old generation.
                   (assert (= stream (self :stream)) "RPC connection changed or closed")
                   (var received false)
                   (def reply
                     (defer (unless received (discard-stream self stream))
                       (send [f args])
                       (++ msg-id)
                       (def reply (recv))
                       (assert (and (tuple? reply) (= 2 (length reply)))
                               "Invalid RPC reply")
                       (set received true)
                       reply))
                   # A remote application error is a complete reply, not
                   # a broken transport. Cancellation or partial I/O above
                   # discards the line before the next caller gets the lock.
                   (let [[ok x] reply]
                     (if ok x (error x))))))))
      self)})

(defn call
  "Calls a freshly looked-up method with bounded transport waits. Set retry-safe
   only for reads or idempotent invalidations: a lost mutation reply is ambiguous."
  [self method args &opt retry-safe]
  (def [ok result]
    (protect
      (unless (self :stream) (:open self))
      (apply (self method) self args)))
  (if ok result
    (if (and retry-safe (not (self :stream)))
      (do (:open self) (apply (self method) self args))
      (error result))))

(defn client
  ```
  Create an RPC client. Returns a table of async functions
  that can be used to make remote calls. This prototype contains
  a `:close` and `:reopen` methods that can be used to close and
  reopen the connection respectively.

  With `:keypair`, the client is known to the server by that static
  `kx/keygen` keypair rather than a new one; with `:server-key`, it talks
  only to the server whose public key that is.
  ```
  [&opt host port name psk &keys {:keypair keypair :server-key server-key}]

  (def client
    (make Client
          :host host
          :port port
          :psk psk
          :name name
          :keypair keypair
          :server-key server-key))
  (:open client))
