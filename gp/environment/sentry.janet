(import ./thicket :export true :prefix "")

(setdyn *handler-defines* [:view :conn])
(defdyn *view* "View for handlers")

(defn ^deregister
  "Deregisters for refresh"
  [peer &opt name]
  (make-watch
    (fn [_ state _]
      (def {:guards guards :tenant tenant} state)
      (default name guards)
      (default tenant name)
      (:deregister (state peer) name tenant))
    (. "deregister " peer)))

(def <form/>
  "hg representation of login form"
  [:form {:method "POST" :class "f-col center"}
   [:input {:type "password" :name "secret"}]
   [:button [:strong "Use"]]])

(defh /index
  "Handler for the form"
  [http/cookies]
  (define :templates)
  (assert templates "Auth templates dynamics must be set in `(dyn :templates)`")
  (def {:page page :title title :success success} templates)
  (def sk (=>header-cookie req))
  (def {:guards guards :session session} view)
  (if ((??? present-string? (?eq sk)) session)
    (do
      (protect
        (:write conn
                (http/html-success-resp
                  (page @[(success guards) <script/redirect/>])))
        (:flush conn))
      (ev/give-supervisor :close conn)
      (produce (^deregister :tree))
      (produce (^write-spawn guards sk))
      (produce Exit))
    (http/html-success-resp (page @[title <form/>]))))

(defh /auth
  "Authentication handler"
  [http/urlenc-post]
  (define :templates)
  (assert templates "Auth templates dynamics must be set in `(dyn :templates)`")
  (def {:page page :success success :failure failure} templates)
  (if-let [sec (view :secret)
           bsec (get body :secret "")
           {:name name :cookie-host cookie-host
            :key key :guards guards} view
           _ (pwhash/verify sec bsec key)]
    (let [sk (derive-from key)]
      (fn [conn]
        (def resp
          (page
            @[(success guards)
              <script/redirect/>]))
        (protect
          (:write conn
                  (http/html-success-resp
                    resp (http/cookie "session"
                                      (string sk "; Secure; HttpOnly; Domain="
                                              cookie-host ";"))))
          (:flush conn))
        (ev/give-supervisor :close conn)
        (produce (^deregister :tree))
        (if-let [auth-hook (dyn :auth-hook)]
          (produce (auth-hook sk)))
        (produce (^write-spawn guards sk))
        (produce Exit)))
    (http/html-success-resp (page @[failure <form/>]))))

(defh /catch-all
  "Handler which catches all paths and redirects to form"
  []
  (match [(req :method) (req :uri)]
    ["POST" u] (/auth req)
    ["GET" (u (string/find "." u))]
    ((http/static (view :public)) req)
    ["GET" u] (/index req)))

(def routes
  "HTTP routes"
  @{"/" (http/dispatch {"GET" /index
                        "POST" /auth})
    :not-found /catch-all})

(define-event PrepareView
  "Initializes handlers' view"
  {:update
   (fn [_ state]
     (put state :view
          (select-keys state [:name :guards :session :secret :key
                              :public :cookie-host])))
   :effect
   (fn [_ state _] (setdyn *view* (state :view)))})

(defn =>sentry/initial-state
  "Navigation to sentry initial state"
  [sentry]
  (let [c @[] t @{}
        =>guards (=> :symbionts sentry :guards)]
    (=> (>if =>guards
             (=> (<- c =>guards)
                 (<:- t :tenant (>or (=> :symbionts |(get $ (array/peek c)) :tenant)
                                     (fn [&] (array/peek c))))
                 (<:= t (=>mycelium/peers
                          (=> :mycelium :nodes |(get $ (array/peek c)))))
                 (<:= t (=> :mycelium :nodes |(get $ (array/peek c))))
                 (<:= t (=> :membranes :nodes |(get $ (array/pop c))))))
        (>base t))))

(defn ^refresh-view
  "Refreshes the data in view from tree"
  [& colls]
  (make-update
    (fn [_ state]
      (def {:tree tree :view view :tenant name} state)
      (each coll colls
        (put view coll (coll tree name))))
    (. "refresh view " ;colls)))

(defr +:refresh
  "RPC function that refreshes the view"
  [ok-resp]
  (define :view)
  (def [what] args)
  (assert (present? what))
  (if ((?eq :session) what)
    (produce (^refresh-view what))))

(defmacro sentry/main
  ```
  Convenience for a sentry contrstruction.
  `events` are transacted afer PrepareView.
  ```
  [& events]
  ~(do
     (-> compile-config
         (make-manager on-error)
         (:transact PrepareView ,;events)
         :await)
     (os/exit 0)))

(defn ^session/new
  "Saves new session on the tree"
  [session]
  (make-effect
    (fn [_ {:tree tree :tenant tenant} _]
      (:session/new tree tenant session))
    "new session"))

(define-watch SpawnExit
  "Conditionaly spawn and exits the manager"
  [_ {:session session :guarded-by sentry :name name} _]
  (producer
    (produce (^session/new "") (^deregister :tree name))
    (if sentry
      (produce (^write-spawn sentry "")))
    (produce Exit)))

(defn check-session
  ```
  Checks if user cookie is in the session. If it is found  `next-middleware`
  is called. If the session is not found it exits.
  ```
  [next-middleware]
  (http/cookies
    (fn check-session [req]
      (define :conn)
      (define :view)
      (def sk (=>header-cookie req))
      (if-let [ck (and sk ((=> :session (?eq sk)) view))]
        (next-middleware (put req :session ck))
        (do
          (ev/give-supervisor :close conn)
          (produce SpawnExit)
          (http/not-authorized))))))

(defh /logout
  "Handles lgout"
  []
  (produce SpawnExit)
  (http/response
    303 ""
    (merge {"Location" "/" "Content-Length" 0})))
