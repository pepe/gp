(import ./base :prefix "" :export true)
(import ../net/uri :export true)

(def . "string" string)

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
     (def {:headers headers :body body :method method :uri uri
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

# RPC
(defdyn *rpc-defines* "Dynamics with what should defined in rpc-fn")

(defn rpc-fn
  ```Constructs anonymous RPC handler function, used by defr and fnr.
The function implicitly defines the rpc argument rpc and binds
dynamics as set by *rpc-defines*.```
  [name body]
  (with-syms [args]
    ~(fn ,name [& ,args]
       (def [rpc & args] ,args)
       ,;(seq [defne :in (dyn *rpc-defines* [])]
           ~(def ,(symbol defne) (dyn ,defne)))
       ,;body)))

(defmacro defr
  "Defines RPC function with features from `rpc-fn`."
  [name docstr middlewares & body]
  ~(def ,name ,docstr
     ,(if (empty? middlewares)
        (rpc-fn name body)
        ~(->
           ,(rpc-fn name body)
           ,;middlewares))))

(defmacro fnr
  "Defines anonymous RPC function with features from `rpc-fn`."
  [name middlewares & body]
  (if (empty? middlewares)
    (rpc-fn name body)
    ~(->
       ,(rpc-fn name body)
       ,;middlewares)))

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

(define-watch Stop
  "Stop the server, flush store and exits"
  [&]
  (producer
    (ev/sleep 0.001)
    (exit)))

(define-watch Netrepl
  "Start the netrepl"
  [_ state _]
  (def {:netrepl nr} state)
  (if nr
    (producer
      (netrepl/server ;(server/host-port nr) (put (curenv) :state state)))))

(define-watch HTTP
  "Creates producer with running HTTP server."
  [_ {:http http :log log? :debug debug
      :routes routes :public public :static static} _]
  (assert http "HTTP host and port must be set, exiting.")
  (assert (table? routes) "Routes must be table, exiting.")
  (if static (assert public "Public path must be set, exiting."))
  (setdyn :debug debug)
  (def parser
    (http/parser
      (cond-> routes
              static (put :not-found (http/static public))
              true http/drive log? event-journal)))
  (producer
    (def chan (ev/chan 128))
    (server/start chan ;(server/host-port http))
    (produce (logf "Starting HTTP server on %s, port %s" ;(server/host-port http)))
    (http/supervisor
      chan
      (http/on-connection parser)
      [:product events] (produce ;events)
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

(defn ^delay
  "Delay the `event` for `s` time"
  [s event]
  (make-watch (producer (ev/sleep s) (produce event)) "delay"))

(define-watch Exit
  "Logs exiting and stops"
  [_ {:name name} _] [(log name " is exiting.") Stop])

(define-watch RPC
  "Creates producer with running RPC server."
  [_ {:rpc {:url url :functions functions} :psk psk :name name} _]
  (assert (present-string? url) "RPC host and port must be set, exiting.")
  (assert (present-string? psk) "RPC psk must be set, exiting.")
  (default functions {})
  (assert (dictionary? functions) "RPC functions must be dictionary, exiting.")
  (setdyn :debug debug)
  (producer
    (let [[host port] (server/host-port url)
          chan (ev/chan 128)]
      (server/start chan host port)
      (produce (logf "Starting %s RPC on %s, port %s" name
                     ;(server/host-port url)))
      (rpc/supervisor
        chan
        (rpc/on-connection
          (merge-into
            @{:psk psk
              :stop (fn [r &]
                      (produce (log name " RPC server going down")
                               Stop)
                      :ok)
              :ping (fn [&] :pong)}
            functions))
        [:product events] (produce ;events)
        [:error fiber]
        (do
          (def err (fiber/last-value fiber))
          (def conn ((fiber/getenv fiber) :conn))
          (produce (log "RPC Supervisor: " err))
          (when (dyn :debug) (produce (stacktrace fiber)))
          (:close conn))))))

(defn ok-resp
  "RPC MW that returns :ok after the body"
  [handler]
  (fn [& args]
    (handler ;args)
    :ok))

(defn produce-resp
  "RPC MW that produces the response of the handler"
  [handler]
  (fn [& args]
    (produce ;(handler ;args))))

(defn on-error
  "Manages errors for events' manager. Transacts detail logging."
  [manager err]
  (:transact
    manager
    ;(match err
       (msg (string? msg)) (log msg)
       ([at event f] (keyword? at) (valid? event) (fiber? f))
       (cond-> @[(logr (string at " failed for " (event :name)
                               " with error: " (fiber/last-value f)))]
               (dyn :debug) (array/push (stacktrace f)))
       (error "Unexpected error type"))))

# Test helpers

(def success?
  "HTTP success validator"
  (??? {:status (?eq 200)}))

(def not-found?
  "HTTP success validator"
  (??? {:status (?eq 404)}))

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

(defn pipe-out
  "Spawns the process with pipe out"
  [[cmd flags]]
  (os/spawn cmd flags {:out :pipe}))

(defn hash
  "Returns hash item"
  [item]
  (and
    item
    (string (util/bin2hex (hash/hash 16 item (dyn :ctx))))))

(defn human
  "Capitalizes and replace -"
  [name]
  (string/join
    (->> name (string/split "-")
         (map |(string (string/ascii-upper
                         (string/from-bytes ($ 0))) (slice $ 1 -1))))
    " "))

(define-watch Ready
  "Event that logs readiness"
  [_ {:name name} _]
  (log (human name) " is ready"))

(def Empty
  "Empty event"
  (make Event))

(def project-files-peg
  "PEG for filewatch"
  '(+
     (* (thru ".janet") -1)
     (* "templates" (thru ".temple") -1)))

(defn chunk-msg
  "Contructs chunk from msg"
  [msg]
  (string/format "%x\r\n%s\r\n" (length msg) msg))

(defn ds/patch-elements
  "Writes patch-elements SSE message to conn"
  [elements &opt selector mode]
  (def msg
    (chunk-msg
      (string
        "event: datastar-patch-elements\n"
        (if selector (string "data: selector " selector "\n"))
        (if mode (string "data: mode " mode "\n"))
        "data: elements " elements "\n\n")))
  (:write (dyn :sse-conn) msg))

(defn ds/hg/patch
  "patch-elements from hg `elements`"
  [elements &opt selector mode]
  (ds/patch-elements (hg/html elements) selector mode))

(defn ds/patch-signals
  "Writes patch-elements SSE message to conn"
  [signals]
  (def msg
    (chunk-msg
      (string
        "event: datastar-patch-signals\n"
        "data: signals " (json/encode signals) "\n\n")))
  (:write (dyn :sse-conn) msg))

(defn ds/get
  "Constructs ds get uri"
  [& parts]
  (string "@get('" ;parts "')"))

(defn ds/post
  "Constructs ds post uri"
  [& parts]
  (string "@post('" ;parts "')"))

(defn ds/hg-stream
  "Convenience for defining SSE stream handler"
  [elements]
  (http/stream
    (each [element selector mode] elements
      (ds/patch-elements (hg/html element) selector mode))))

(defn ds/input
  "Datastar input helper"
  [name & attrs]
  [:input (struct ;attrs :data-bind name)])

(defn ds/select
  "Datastar select helper"
  [name options]
  [:select {:data-bind name} options])

(defmacro init-test
  "Initializes test defs and store"
  [symbiont]
  (def now (- (os/time) 10))
  (def store-name (symbol symbiont "-store"))
  ~(upscope
     (def {:http http-url
           :image image
           :key key
           :rpc rpc-url
           :psk psk} ((=>symbiont-initial-state ,symbiont) compile-config))
     (def test-store
       (when image
         (def image-file (string image ".jimage"))
         (if (os/stat image-file) (os/rm image-file))
         (:init (make Store :image image))))
     (defn url [path] (string "http://" http-url path))))

(defn ds/query
  "Convenience that parses query params datastar data"
  [next-middleware]
  (fn [req]
    (next-middleware
      ((http/query-params
         (fn [req]
           (def c @[])
           ((=>
              (<- c
                  (=> :query-params "datastar"
                      (>if present?
                           (=> json/decode (>map-keys keyword)
                               (>map-vals (=> (>if string? |(string/replace-all "+" " " $))))))))
              |(put $ :datastar (array/pop c))) req))) req))))

(defn shlc
  "Joins `parts` and make sh -lc"
  [& parts]
  [:sh "-lc" (string/join parts " ")])

(defn jdn/render
  "Renders Janet `item` into jdn"
  [item]
  (string/format "%j" item))

(defmacro defargs
  "Convenience for defining arguments"
  [binding]
  ~(def ,binding args))

(def- digits
  ["zero" "one" "two" "three" "four" "five" "six"
   "seven" "eight" "nine" "ten"])

(defn digit->word
  "Map from digit to word"
  [digit]
  (get digits digit))

(defn word->digit
  "Map from word to digit"
  [word]
  (find-index (?eq word) digits))

(defn update-rpc
  "Prepares RPC configuration"
  [funcs]
  (fn [url] @{:url url :functions funcs}))

(def >stamp
  "Function that timestamps"
  (>put :timestamp (os/time)))

(def =>header-cookie
  "Navigate to cookie in request headers"
  (=> :headers "Cookie" "session"))

(defn ^write-spawn
  "Writes the spawn command to stdout"
  [peer arg]
  (make-effect
    (fn [_ {:dry dry} _]
      (unless dry
        (:write stdout (marshal [peer arg]))
        (:flush stdout)))
    "write spawn"))

(defn pipe-out
  "Spawns the process with pipe out"
  [[cmd flags]]
  (os/spawn cmd flags {:out :pipe}))

(define-watch Ready
  "Event that logs readiness"
  [_ {:name name} _]
  (log (human name) " is ready"))

(defn shlc
  "Joins `parts` and make sh -lc"
  [& parts]
  [:sh "-lc" (string/join parts " ")])

(defn derive-from
  "Derives new key from master `key`"
  [key]
  (setdyn :ctx "intrstdy")
  (->> key
       (kdf/derive-from-key 16 (os/time) (dyn :ctx))
       util/bin2hex
       freeze))

(def <script/redirect/>
  "hg representation of the redirect script"
  [:script
   (hg/raw
     ``function redirect() {
         document.location = "/";
       }
       setTimeout(redirect, 250);``)])
