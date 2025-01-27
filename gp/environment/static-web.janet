(import ./app :prefix "" :export true)
(import /templates/app)
(import /templates/dashboard)
(import /templates/edit)
(import /templates/new-content)
(import /templates/upload)

(setdyn *handler-defines* [:state :resolve :conn])

(defn- files-with-mod [dir]
  (tabseq [[i f] :pairs (sh/list-all-files dir)] f (os/stat f :modified)))

(defn mdz->html
  "Changes mdz to html externsion"
  [file &opt prefix]
  (default prefix "")
  (->> file
       (string/replace "content" prefix)
       (string/replace "mdz" "html")))

(defn process-css
  "Process css"
  [e]
  (def {:static s
        :css css
        :files {:css fcss}} e)
  (->>
    fcss
    (map |(string/replace (path/join s css) css $))
    (filter |(string/has-suffix? ".css" $))
    sort))

(defn fix-nl
  "Fix end line to unix"
  [fc]
  (string/replace-all "\r\n" "\n" fc))

(defn monitor
  ```
  Creates event, that monitors directory `dir` and produces result of calling 
  `fun` with name of the file that changes.
  ```
  [dir fun]
  (make-watch
    (fn [&]
      (producer
        (def c (ev/chan 0))
        (def fw (filewatch/new c))
        (filewatch/add fw dir :creation :last-write :recursive)
        (filewatch/listen fw)
        (forever
          (def event (ev/take c))
          (when (string/find "." (event :file-name))
            (def file-path (path/join (event :dir-name) (event :file-name)))
            (produce (log "File " file-path " was " (event :type))
                     (fun file-path))))))))

(define-watch Present
  "Prints present message"
  [_ {:site-title t} _]
  (log "\n" (string/repeat "-" 40)
       "\n" t " construction starts"))

(define-update SetDev
  "Sets dev in the state"
  [_ e] (put e :dev true))

(defn save-content
  "Saves content to the file"
  [file content]
  (make-effect
    (fn [_ {:content c :public p} _]
      (def nf
        (->> file
             (string/replace c p)
             (string/replace "mdz" "html")))
      (def dir (path/dirname nf))
      (if (not (os/stat dir)) (os/mkdir dir))
      (spit nf content)
      (print "Rendered " file " to " nf))
    (string "save-content-" file)))

(var env
  (merge-into
    (require "spork/mdz" :prefix "")
    (require "/app/markup" :prefix "")))

(defn save-markup [file markup]
  (make-update
    (fn [_ state] ((=> :markups (>put file (select-keys markup [:front-matter :markup-dom]))) state))
    (string "save-markup" file)))

(defn markup-post-file [file]
  (make-watch
    (fn [&]
      (save-markup file (mdz/markup (slurp (string "./" file)) env file)))
    (string "markup-post-file" file)))

(defn index? [file]
  (string/find "index" file))

(defn render-post-file [file]
  (make-watch
    (fn [_ e _]
      (try
        (let [{:site-title st :dev dev
               :files {:posts pfiles} :logos logos
               :markups mds} e
              m (mds file)
              fm (m :front-matter)
              mt (fm :template)
              rt (and mt (temple/compile (slurp (string "." mt ".temple"))))
              pfs
              (if (fm :index)
                (sort pfiles
                      (fn [a b]
                        (let [mad (get-in mds [a :date])
                              mbd (get-in mds [b :date])]
                          (> mad mbd)))) [])
              args (merge (m :front-matter)
                          {:current-file file
                           :content (hg/html (m :markup-dom))
                           :site-title st :css (process-css e)
                           :logo logos :dev dev :posts pfs :markups mds})]
          (save-content file (rt ;(kvs args))))
        ([e f] [(log "Error: " e " when rendering file: " file) (stacktrace f)])))
    (string "render-post-file" file)))

(defn render-content-file
  "Renders mdz file"
  [file]
  (make-watch
    (fn [_ e _]
      (try
        (let [{:site-title st :dev dev :static s :logos logos :markups mds} e
              m (mdz/markup (slurp (string "./" file)) env file)
              mt (get-in m [:front-matter :template])
              rt (temple/compile (slurp (string "." mt ".temple")))
              args (merge (m :front-matter)
                          {:current-file file
                           :content (hg/html (m :markup-dom))
                           :site-title st :css (process-css e)
                           :logo logos :dev dev
                           :news ((=> pairs (>Y (=> last :front-matter :type (?eq "news")))) mds)
                           :events ((=> pairs (>Y (=> last :front-matter :type (?eq "events")))) mds)})]
          (save-content file (rt ;(kvs args))))
        ([err fib]
          [(log "Error: " err " when rendering file: " file)
           (stacktrace fib)])))
    (string "render-content-" file)))

(define-watch RenderContent
  "Renders all content files"
  [_ {:files {:content cf}} _]
  (seq [f :in cf] (render-content-file f)))

(define-watch RenderPosts
  "Renders all post files"
  [_ {:files {:posts bf}} _]
  (seq [f :in bf] (render-post-file f)))

(define-watch MarkupPosts [_ {:files {:posts bf}} _]
  (seq [f :in bf] (markup-post-file f)))

(defn copy-file
  "Copies file from static to public"
  [file]
  (make-effect
    (fn [_ {:public p :static s} _]
      (def nf
        (string/replace s p file))
      (sh/copy-file file nf)
      (print "Copied " file " to " nf))
    (string "copy-file-" file)))

(define-watch CopyFiles
  "Copy all files and images"
  [_ {:files {:css cf :img im :js js}} _]
  (seq [f :in (array/concat cf im js)] (copy-file f)))

(defn save-files
  "Save all files to state"
  [dir files]
  (make-update
    (fn [_ e] (put-in e [:files dir] files))
    (string "save-files-" dir)))

(defn list-ext
  ```
  List all files in the `dir`. If provided one or more `exts` filenames
  are filtered with it.
  ```
  [dir & exts]
  (cond->> (map |(path/join dir $) (os/dir dir))
           (not (empty? exts))
           (filter |(some (fn [ext] (string/has-suffix? ext $)) exts))))

(defn list-all-ext
  ```
  List all files in the `dir`. If provided one or more `exts` filenames
  are filtered with it.
  ```
  [dir & exts]
  (cond->> (sh/list-all-files dir)
           (not (empty? exts))
           (filter |(some (fn [ext] (string/has-suffix? ext $)) exts))))

(define-watch ListPosts
  "Lists all posts files"
  [_ {:posts cd} _]
  (save-files :posts (list-ext cd "mdz")))

(define-watch ListContent
  "Lists all content files"
  [_ {:content cd} _]
  (save-files :content (list-ext cd "mdz")))

(define-watch ListCss
  "Lists all css files"
  [_ {:static s :css cd} _]
  (save-files :css (list-all-ext (path/join s cd) "css" "woff2")))

(define-watch ListImg
  "Lists all img files"
  [_ {:static s :img cd} _]
  (save-files :img (list-all-ext (path/join s cd))))

(define-watch ListJs
  "Lists all js files"
  [_ {:static s :js cd} _]
  (save-files :js (list-all-ext (path/join s cd) "js")))

(define-watch CopyLogo
  "Copies logo image"
  [_ {:static s :logo logo} _]
  (copy-file (path/join s logo)))

(define-update SlurpLogo
  "Slurps logo"
  [_ e]
  (def {:public p :logo l} e)
  (put e :logos (slurp (path/join p l))))

(define-watch Rendering
  "All rendering events"
  [&]
  [ListCss
   ListImg
   ListJs
   CopyFiles
   CopyLogo
   SlurpLogo
   ListPosts
   MarkupPosts
   RenderPosts
   ListContent
   RenderContent
   (log "Rendered everything" "\n")])

(defn refresh-module
  "Refresh module cache for the file-path"
  [file-path]
  (make-event
    {:watch (fn [&] [MarkupPosts
                     RenderPosts
                     RenderContent
                     (log "Module on " file-path " refreshed")])
     :effect (fn [&]
               (put module/cache (path/posix/join ;(path/parts file-path)) nil)
               (set env (merge-into
                          (require "spork/mdz" :prefix "")
                          (require "/app/markup" :prefix ""))))}
    (string "refresh-module" file-path)))

(define-watch ContentMonitors
  "Runs all the monitors"
  [&]
  [(monitor "./static" |(case $ "logo.svg" CopyLogo (copy-file $)))
   (monitor "./content/posts" render-post-file)
   (monitor "./content" render-content-file)])

(define-watch CodeMonitors
  "Runs all the monitors"
  [&]
  [(monitor "./app" refresh-module)
   (monitor "./templates" refresh-module)])

(defn <file-tr/>
  "Renders htmlgen representation of one file"
  [f]
  (def vf (mdz->html f))
  [:tr
   [:td f]
   [:td {:class "f-row"}
    [:a {:class "<button>" :href (string "/__dashboard/render?file=" f)} "Render"]
    [:a {:class "<button>" :href (string "/__dashboard/edit?file=" f)} "Edit"]
    [:a {:href vf} "View"]]])

(defn <static-file-tr/>
  "Renders htmlgen representation of one static file"
  [f]
  (def vf (string/replace "static\\" "" f))
  [:tr
   [:td f]
   [:td
    [:a {:href vf} "View"]]])

(defh /dashboard
  "Handler for the dashboard page"
  [(http/guard-methods "GET") http/html-success]
  (def {:site-title st :css css :files fs :posts ps} state)
  (app/capture
    :title "Dashboard"
    :site-title st
    :css (process-css state)
    :content (dashboard/capture :content-files ((=> :content (>map <file-tr/>) hg/html) fs)
                                :posts-files ((=> :posts (>map <file-tr/>) hg/html) fs)
                                :static-files ((=> :css (>map <static-file-tr/>) hg/html) fs))))

(defh /render
  "Handler for render action"
  [(http/guard-methods "GET") http/query-params]
  (def {:query-params {"file" file}} req)
  (if (= file "all")
    (do
      (produce RenderContent)
      (http/see-other "/"))
    (do
      (produce (render-content-file file))
      (http/see-other (mdz->html file)))))

(defh /edit
  "Handler for the edit page"
  [http/query-params (http/guard-methods "GET") http/html-success]
  (def {:site-title st :css css :files fs} state)
  (def {:query-params {"file" file}} req)
  (def fc
    (if (= :file (os/stat file :mode))
      (slurp file)
      (new-content/capture :author (state :author)
                           :templates (state :templates))))
  (app/capture
    :title (string "Editing " file)
    :site-title st
    :css (process-css state)
    :content (edit/capture :file-content fc
                           :file-name file)))

(defh /save
  "Handler for the save action"
  [(http/guard-methods "POST") http/urlencoded]
  (def {"file-name" fnm "file-content" fc} body)
  (def san-fnm
    (let [trfn (string/trim fnm)]
      (cond-> fnm
              (not (string/has-suffix? ".mdz" trfn)) (string ".mdz")
              (not (string/has-prefix? "content" trfn)) (path/join "content"))))
  (spit san-fnm (fix-nl (string/trim fc))) # TODO add event
  (produce (render-content-file san-fnm) ListContent)
  (http/response 303 "" {"Location" (mdz->html san-fnm) "Content-Length" 0}))
(trace /save)

(defh /upload
  "Handler for the upload action"
  [(http/guard-methods "GET") http/html-success]
  (app/capture
    :title (string "Upload new image file")
    :site-title (state :site-title)
    :css (process-css state)
    :content (upload/capture)))

(defh /process
  "Handler process uploaded image"
  [(http/guard-methods "POST") http/multipart]
  (spit (path/join (state :static) (body "path")) (gett body "content" :content))
  (produce ListImg)
  (http/see-other "/__dashboard"))

(def routes
  "Application routes"
  @{"/__dashboard"
    {"" /dashboard
     "/render" /render
     "/edit" /edit
     "/save" /save
     "/upload" /upload
     "/process" /process}
    :not-found (http/static "public")})


(def resolving
  "Application resolving"
  (route/resolver
    {"/__dashboard" :dashboard
     "/render" :render
     "/edit" :edit
     "/save" :save
     "/upload" :upload
     "/process" :process}))

(define-event PrepareState
  "Prepares routes in state"
  {:update
   (fn [_ state]
     (merge-into state
                 {:routes routes
                  :resolve
                  (fn [action & params]
                    (resolving action (table ;params)))}))
   :effect (fn [_ state _]
             (def {:routes routes :resolve resolve} state)
             (setdyn :state state)
             (setdyn :routes routes)
             (setdyn :resolve resolve))})

(def env-init
  "Events per environment"
  {"dev" [PrepareState HTTP Rendering SetDev Present ContentMonitors CodeMonitors]
   "watch" [PrepareState HTTP Rendering SetDev Present ContentMonitors]
   "prod" [Rendering Present]})
