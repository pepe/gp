(import ./app :export true :prefix "")

(setdyn *handler-defines* [:view :conn])
(defdyn *view* "View for handlers")

(def <form/>
  "hg representation of login form"
  [:form {:method "POST" :class "f-col center"}
   [:input {:type "password" :name "secret"}]
   [:button [:strong "Use"]]])

(defh /index
  "Handler for the form"
  [http/cookies http/html-get]
  (define :templates)
  (assert templates "Auth templates dynamics must be set in `(dyn :templates)`")
  (def {:page page :title title} templates)
  (page @[title <form/>]))

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
              [:script
               (hg/raw
                 ``function redirect() {
                     document.location = "/";
                   }
                   setTimeout(redirect, 1000);``)]]))
        (:write conn
                (http/html-success-resp
                  resp (http/cookie "session"
                                    (string sk "; Secure; HttpOnly; Domain="
                                            cookie-host ";"))))
        (ev/give-supervisor :close conn)
        (produce (^write-spawn guards sk) Exit)))
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

(defn =>sentry-initial-state
  "Navigation to sentry initial state"
  [=>symbiont-initial-state sentry]
  (=> (=>symbiont-initial-state sentry)
      (>put :routes routes)
      (>put :static false)
      (>update :rpc (update-rpc @{}))))

(defmacro sentry-main
  []
  '(do (-> initial-state
           (make-manager on-error)
           (:transact PrepareView HTTP RPC)
           :await)
     (os/exit 0)))

(define-watch SpawnExit
  "Conditionaly spawn and exits the manager"
  [&]
  (producer
    (if-let [[peer arg] (dyn :spawn-after)]
      (produce (^write-spawn peer arg)))
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
