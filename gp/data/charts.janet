(use spork/htmlgen spork/misc)

(defn- render-axis
  "Renders optional axis"
  [chart content]
  (def {:height height :width width} (chart :config))
  (def res @[:g {:class "axis"}])
  (array/push res [:line {:x1 0 :y1 0 :x2 0 :y2 height}])
  (array/push res [:line {:x1 0 :y1 height :x2 height
                          :y2 height}])

  (array/push content res))

(defn- render-bar
  "Renders bar chart"
  [chart content]
  (def {:height height :width width} (chart :config))
  (let [d (chart :data)
        ld (length d)
        iw (/ width ld)
        mx (max 0 ;d) mn (min 0 ;d) ex (- mx mn)
        ih (/ height ex)
        zero (- height (* -1 mn ih))]
    (def res @[:g {:class "chart bar"}])
    (loop [[i p] :pairs d :let [ph (math/abs (* p ih))
                                x (* i iw)
                                y (if (pos? p) (- zero ph) zero)]]
      (array/push res [:rect {:x x :y y :width iw :height ph}]))
    (array/push content res)
    (when (get-in chart [:config :axis])
      (render-axis chart content))))

(def default-config
  "Default configuration."
  {:width 1000 :height 1000 :axis false
   :svg @{:version "1.1" :xmlns "http://www.w3.org/2000/svg"}})

(def Chart
  "Prototype for a Chart."
  @{:config default-config
    :data []
    :render
    (fn render
      [chart]
      (def {:height height :width width :type typ} (chart :config))
      (def content @[])
      (case typ
        :bar (render-bar chart content)
        (error "Unknown graph type"))
      (freeze [:svg (merge (get-in chart [:config :svg])
                           {:width width :height height}) ;content]))})

(defn render
  ```
  Renders chart with `type`, `data`. Optional `config` key value pairs get
  merged with `default-config`.
  ```
  [type data & config]
  (def conf
    (cond-> (merge default-config {:type type})
            (not (empty? config)) (merge (table ;config))))
  (:render (make Chart :config conf :data data)))
