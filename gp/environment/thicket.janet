(import gp/environment/app :prefix "" :export true)

(defn ^connect-peer
  "Connects to one peer"
  [peer &opt succ]
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
         (def {:name name} state)
         (var failed false)
         (var tries 0)
         (while
           (match [(protect (:open (state peer))) tries]
             [[true _] _] (produce (log name " connected to " peer))
             [[false _] 10] (produce (log name " cannot connect to " peer "."))
             true)
           (ev/sleep (* (++ tries) 0.1)))
         (if succ (produce ;succ))))}
    (. "connect peer " peer)))

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
         (def {:peers peers :name name} state)
         (var failed false)
         (each peer peers
           (var tries 0)
           (while
             (match [(protect (:open (state peer))) tries]
               [[true _] _] (produce (log name " connected to " peer))
               [[false _] 10] (do
                                (set failed true)
                                (produce (log name " cannot connect to " peer ".")))
               true)
             (ev/sleep (* (++ tries) 0.1))))
         (if failed (produce fail) (produce succ))))}
    "connect peers"))

(defn ^register
  "Registers for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:register (state peer) (state :name)))
    (. "register " peer)))

(defn ^deregister
  "Deregisters for refresh"
  [peer]
  (make-watch
    (fn [_ state _]
      (:deregister (state peer) (state :name)))
    (. "deregister " peer)))

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
      (def {:tree tree :view view :tenant tenant :name name} state)
      (default tenant name)
      (each coll colls
        (put view coll (coll tree tenant))))
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

(defn =>mycelium/node
  "Navigation to symbiont mycelium"
  [symbiont]
  (def c @[])
  (>or (=> :mycelium :nodes symbiont)
       (>when (=> :symbionts symbiont :guards)
              (=> (<- c (=> :symbionts symbiont :guards))
                  (=> :mycelium :nodes |(get $ (array/pop c)))))))

(defn =>mycelium/peers
  "Navigation to `symbiont` peers"
  [=>mycelium]
  (let [c @[]
        =>peers (=> =>mycelium :peers)]
    (>if (=> =>peers present?)
         (=> (<- c (=> =>peers))
             |(tabseq [i :in (array/pop c)]
                i ((=> (=>mycelium/node i) :rpc) $)))
         (>base {}))))
