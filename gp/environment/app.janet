(import ./base :prefix "" :export true)
(import ../net/uri :export true)

# HTTP utils
(defdyn *handler-defines* "Dynamics that should be defined in the handler")
(defdyn *heart-tick* "Rate for the `heart-beat` producer")

(defn handler-fn
  ```
  Constructs anonymous handler function, which is used by
  `defh` and `fnh` macros.
  The function implicitly defines the request `req` and derivate values:
  `headers`, `body`, `params` and `query-params`.
  It also defines dynamics as set by `*handler-defines*`.
  ```
  [name body]
  ~(fn ,name [req]
     (def {:headers headers :body body
           :params params :query-params query-params} req)
     ,;(seq [defne :in (dyn *handler-defines* [])]
         ~(def ,(symbol defne) (dyn ,defne)))
     ,;body))

(defmacro defh
  "Defines handler function with with features from `handler-fn`."
  [name docstr middlewares & body]
  ~(def ,name ,docstr
     ,(if (empty? middlewares)
        (handler-fn name body)
        ~(->
           ,(handler-fn name body)
           ,;middlewares))))

(defmacro fnh
  "Defines anonymous handler function with features from `handler-fn`."
  [name middlewares & body]
  (if (empty? middlewares)
    (handler-fn name body)
    ~(->
       ,(handler-fn name body)
       ,;middlewares)))

(defn process-body
  ```
  If body is dictionary it constructs urlencoded string from it,
	or returns it unchanged.
  ```
  [body]
  (if (dictionary? body)
    (let [b @""]
      (loop [[k v] :pairs body]
        (buffer/push-string b (if (empty? b) "" "&")
                            (uri/escape (string k)) "=" (uri/escape v)))
      (string b))
    body))

(defn coerce-body
  "Corce keys to keyword and trim vals"
  [body]
  (map-vals string/trim (map-keys keyword body)))

# Events
(define-update Dirty
  "Marks store as dirty"
  [_ state]
  (put state :dirty true))

(define-update Clean
  "Marks store as clean"
  [_ state]
  (put state :dirty false))

(define-event Flush
  "Flushes the store"
  {:watch (fn [&] [(log "Flushing store") Clean])
   :effect (fn [_ {:store store} _]
             (:flush store)
             (gccollect))})

(defn heart-beat
  ```
  Periodic heart beat event. `event-pairs` should be in fromat
  `events` `predicate`. Produces `events` if the `predicate` is truthy
  for the `heart` counter and the manager's `state`.

  Tick duration could be set by the `*heart-tick*` dynamic and
  defaults to 1 second.
  ```
  [& event-pairs]
  (assert (even? (length event-pairs)))
  (def rules (partition 2 event-pairs))
  (make-watch
    (fn [_ state _]
      (producer
        (def tick (dyn *heart-tick* 1))
        (var heart tick)
        (forever
          (each [events pred] rules
            (if (pred heart state) (produce ;events)))
          (ev/sleep tick)
          (++ heart))))
    "heart-beat"))

(define-event PrepareStore
  "Prepares store in the state."
  {:update (fn [_ state] (put state :store (make Store :image (state :image))))
   :watch (fn [_ {:image image :log log?} _]
            (if log? (log "Initializing store image named " image)))
   :effect (fn [_ {:store s} _] (:init s) (gcsetinterval 0x7FFFFFFF))})

(define-effect Stop
  "Stop the server, flush store and exits"
  [_ {:store store} _]
  (ev/sleep 0.1) (:flush store) (os/exit))

(define-watch Netrepl
  "Start the netrepl"
  [_ state _]
  (def {:netrepl nr} state)
  (if nr
    (producer
      (netrepl/server ;(server/host-port nr) (put (curenv) :state state)))))

(define-watch HTTP
  "Creates producer with running HTTP server."
  [_ {:http http :view view :resolve resolve :key key :log log?
      :routes routes :public public :static static} _]
  (def parser
    (http/parser
      (cond-> routes
              static (put :not-found (http/static public))
              true http/drive log? event-journal)))
  (producer
    (def chan (ev/chan 128))
    (server/start chan ;(server/host-port http))
    (http/supervisor
      chan
      (http/on-connection parser)
      [:product events] (produce ;events)
      [:stop fiber]
      (do (:close ((fiber/getenv fiber) :conn)) (break))
      [:error fiber]
      (with [conn ((fiber/getenv fiber) :conn)]
        (when conn
          (def err (fiber/last-value fiber))
          (eprint "HTTP Supervisor: " err)
          (when (dyn :debug) (debug/stacktrace fiber))
          (protect
            (:write conn
                    (http/internal-server-error
                      (string "Internal Server Error: " err)))))))))

(define-watch RPC
  "Creates producer with running RPC server."
  [_ {:rpc {:url url :functions functions :psk psk} :store store :env env} _]
  (default functions {})
  (producer
    (let [[host port] (server/host-port url)
          chan (ev/chan)]
      (server/start chan host port)
      (rpc/supervisor
        chan
        (rpc/on-connection
          (merge-into
            @{:psk psk
              :stop (fn [&] (produce (log "Servers are going down") Stop) :dying)}
            functions))
        [:product events] (produce ;events)
        [:error fiber]
        (do
          (def err (fiber/last-value fiber))
          (def conn ((fiber/getenv fiber) :conn))
          (produce (log "RPC Supervisor: " err))
          (when (dyn :debug) (produce (stacktrace fiber)))
          (:close conn))))))

(define-watch Present
  "Creates event that prints present message for the server"
  [_ {:http http :rpc rpc :log log?} _]
  (when log?
    (def {:url rpc} (or rpc {}))
    (cond-> @[]
            http (array/push (logf "Starting HTTP server on %s, port %s" ;(server/host-port http)))
            rpc (array/push (logf "Starting RPC server on %s, port %s" ;(server/host-port rpc))))))

(defn on-error
  "Manages errors for events' manager. Transacts detail logging."
  [manager err]
  (:transact
    manager
    ;(match err
       (msg (string? msg)) (log msg)
       ([at event f] (keyword? at) (valid? event) (fiber? f))
       (cond-> @[(log (string at " failed for " (event :name)
                              " with error: " (fiber/last-value f)))]
               (dyn :debug) (array/push (stacktrace f)))
       (error "Unexpected error type"))))

# Test helpers

(def success?
  "HTTP success validator"
  (??? {:status (?eq 200)}))

(defn success-has?
  "HTTP success with `parts` validator"
  [& parts]
  (??? {:status (?eq 200)
        :body (?find ;parts)}))

(defn success-has-not?
  "HTTP success without `part` validator"
  [& parts]
  (??? {:status (?eq 200)
        :body (complement (?find ;parts))}))

(defn redirect?
  "HTTP redirect to `location` validator"
  [location]
  (??? {:status (?eq 303)
        :headers (??? {"content-length" (?eq "0")
                       "location" (?eq location)})}))

(def empty-success?
  "HTTP success with empty body validator"
  (??? success? {:body empty?}))

# Misc
(defn make-send-email
  "Constructs function that sends emails with cli curl"
  [url me pwd]
  (fn :make-send-email
    [to file]
    (def [email] (peg/match '(* (thru "<") '(to ">")) me))
    (os/execute
      ["curl" "--ssl-reqd" "--url" url "--user" (string email ":" pwd)
       "--mail-from" email "--mail-rcpt" to "--upload-file" file] :px
      {:out (sh/devnull)})))

(defn timestamp
  "Timestamps entity `o`"
  [o]
  (put o :timestamp (os/time)))
