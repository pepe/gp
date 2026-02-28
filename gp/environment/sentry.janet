(import ./app :export true :prefix "")
(import ./templates/auth-form :export true)
(import ./templates/redirect :export true)

(setdyn *handler-defines* [:view :conn])
(defdyn *view* "View for handlers")

(defh /index
  "Handler for the form"
  [http/cookies http/html-get]
  (auth-form/capture :title (human (view :name))))

(defh /auth
  "Authentication handler"
  [http/urlenc-post]
  (if-let [sec (view :secret)
           bsec (get body :secret "")
           {:name name :cookie-host cookie-host :key key :guards guards} view
           _ (pwhash/verify sec bsec key)]
    (let [sk (derive-from key)]
      (fn [conn]
        (:write conn
                (http/html-success-resp
                  (redirect/capture :to guards :title name :location "/")
                  (http/cookie "session"
                               (string sk "; Secure; HttpOnly; Domain="
                                       cookie-host ";"))))
        (ev/give-supervisor :close conn)
        (produce (^write-spawn guards sk) Exit)))
    (http/html-success-resp
      (auth-form/capture :error "<h2>Authentication failed</h2>"))))

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
