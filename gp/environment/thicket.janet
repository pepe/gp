(import gp/environment/app :prefix "" :export true)

(defn ^connect-peer
  "Connects to one peer"
  [peer]
  (make-event
    {:update
     (fn [_ state]
       (def {:psk psk :name name} state)
       (def url (state peer))
       (when (string? url)
         (def [host port] (server/host-port url))
         (put state peer
              (make rpc/Client
                    :host host :port port
                    :psk psk :name name))))
     :watch
     (fn [_ state _]
       (producer
         (var failed false)
         (var tries 0)
         (while
           (match [(protect (:open (state peer))) tries]
             [[true _] _] (produce (log "Connected to " peer))
             [[false _] 10] (produce (log "Cannot connect to " peer "."))
             true)
           (ev/sleep (* (++ tries) 0.1)))))}
    "connect peer"))

(defn ^connect-peers
  "Connects to all the peers"
  [succ &opt fail]
  (default fail succ)
  (make-event
    {:update
     (fn [_ state]
       (def {:psk psk :name name :peers peers} state)
       (each peer peers
         (def url (state peer))
         (unless (table? url)
           (def [host port] (server/host-port url))
           (put state peer
                (make rpc/Client
                      :host host :port port
                      :psk psk :name name)))))
     :watch
     (fn [_ state _]
       (producer
         (def {:peers peers} state)
         (var failed false)
         (each peer peers
           (var tries 0)
           (while
             (match [(protect (:open (state peer))) tries]
               [[true _] _] (produce (log "Connected to " peer))
               [[false _] 10] (do
                                (set failed true)
                                (produce (log "Cannot connect to " peer ".")))
               true)
             (ev/sleep (* (++ tries) 0.1))))
         (if failed (produce fail) (produce succ))))}
    "connect peers"))


(defn ^register
  "Registers for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:register (state peer) (state :name)))))

(define-watch ClosePeers
  "Closes all connections to peers"
  [_ state _]
  (def {:peers peers} state)
  (each peer peers (protect (:close (state peer)))))

(defn close-peers-stop
  "RPC function that closes peers and stops the server"
  [&]
  (produce ClosePeers
           (log "RPC server going down")
           Stop)
  :ok)

(defn ^refresh-view
  "Refreshes the data in view from tree"
  [& colls]
  (make-update
    (fn [_ state]
      (def {:tree tree :view view :name name} state)
      (each coll colls
        (put view coll (coll tree name))))
    (. "refresh view " ;colls)))

(defn fixtures
  "Combine members of the `sets` to get `n` uniq combinations"
  [n & sets]
  (def rng (math/rng (os/cryptorand 8)))
  (def res @{})
  (while (< (length res) n)
    (put res
         (freeze
           (seq [set :in sets :let [ls (length set)]]
             (get set (math/rng-int rng ls))))
         true))
  (keys res))
