(use ./utils)

# @todo: make this dyn
(def chars
  "Characters considered part of the route"
  '(+ :w (set "-_.")))

(def sep "Separator character" "/")

(def pref "Param prefix character" ":")

(def grammar
  "PEG grammar to match routes with"
  (peg/compile
    {:sep sep
     :pref pref
     :path ~(some ,chars)
     :param '(* :pref :path)
     :capture-path '(<- :path)
     :main ~(some (* :sep
                     (+ (if :param ,(<-: :param :pref :capture-path))
                        (if :path ,(<-: :path :capture-path))
                        (if -1 ,(<-: :root '(constant -1))))))}))

(defn- compile-route
  ```
  Compiles a single route template string (e.g. "/home/:id") into a PEG
  that matches concrete URIs and captures `[:param-name "value"]` pairs
  for each `:param` segment in the template.
  ```
  [route]
  (-> (seq [[pt p] :in (peg/match grammar route)]
        (case pt
          :root (tuple '* sep p)
          :path (tuple '* sep p)
          :param (tuple '* sep
                        ~,(<-: p ~(<- (some ,chars))))))
      (array/insert 0 '*)
      (array/push -1)
      splice
      tuple
      peg/compile))

(defn- extract-args
  "Extracts arguments from peg match"
  [route-grammar uri]
  (when-let [p (peg/match route-grammar uri)]
    (table ;(flatten p))))

(defn- param-count
  "Counts the :param segments in a route template"
  [route]
  (count (fn [[pt _]] (= pt :param)) (peg/match grammar route)))

(defn compile-routes
  ```
  Compiles a `{route-template action}` table into an array of
  `[compiled-peg action]` pairs. Non-string keys in `routes` are
  ignored. Routes are ordered by ascending number of `:param` segments,
  so that between overlapping templates (e.g. "/home/new" and
  "/home/:id"), the one with fewer params is tried first. Routes with
  the same param count keep `routes`' own iteration order relative to
  each other, which is not guaranteed to be declaration order.
  ```
  [routes]
  (def pairs (seq [[route action] :pairs routes :when (string? route)] [route action]))
  (map (fn [[route action]] [(compile-route route) action])
       (sort-by (fn [[route _]] (param-count route)) pairs)))

(defn lookup
  ```
  Looks up `uri` against `compiled-routes` (as returned by `compile-routes`)
  and returns the `[action params]` of the first matching route. Returns
  the empty array `[]` when no route matches.
  ```
  [compiled-routes uri]
  (var matched [])
  (loop [[grammar action] :in compiled-routes :while (empty? matched)]
    (when-let [args (extract-args grammar uri)] (set matched [action args])))
  matched)

(defn router
  ```
  Creates a router function from `routes` (a `{route-template action}`
  table, see `compile-routes`). The returned function takes a `path`
  string and returns `[action params]` for the first matching route, or
  `[]` if none match (see `lookup`).
  ```
  [routes]
  (def compiled-routes (compile-routes routes))
  (fn [path] (lookup compiled-routes path)))

(defn resolver
  ```
  Creates a resolver function from `routes` (a `{route-template action}`
  table). The returned function takes an `action` and an optional
  `params` table, and returns the route template with each `:param`
  placeholder replaced by `(string (params param))`. Throws if `action`
  has no matching route. If `params` omits a placeholder the template
  requires, that placeholder is left in the output as-is rather than
  raising an error.
  ```
  [routes]
  (def inverted-routes (invert routes))
  (fn [action &opt params]
    (def template (assert (get inverted-routes action) (string/format "Route %s does not exist" action)))
    (if params
      (let [params-grammar (seq [[k v] :pairs params]
                             ~(/ (<- (* ":" ,(string k) (not ,chars))) ,(string v)))]
        (first (peg/match ~(% (any (+ ,;params-grammar (<- 1)))) template)))
      template)))
