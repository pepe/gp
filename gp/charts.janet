(use spork/htmlgen spork/misc)

(defn- opt-axis
  "Renders optional axis"
  [chart content]
  (def {:height height :width width} (chart :config))
  (when (get-in chart [:config :axis])
    (def res @[:g {:class "axis"}])
    (array/push res [:line {:x1 0 :y1 0 :x2 0 :y2 height}])
    (array/push res [:line {:x1 0 :y1 (- height 0) :x2 (- width 0)
                            :y2 (- height 9)}])

    (array/push content res)))

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
                                y (math/floor (if (pos? p)
                                                (- zero ph)
                                                zero))]]
      (array/push res [:rect {:x x :y y :width iw :height ph}]))

    (array/push content res)
    (opt-axis chart content)))

(def default-config
  "Default configuration"
  {:margin 0 :width 1000 :height 1000
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
  "Renders chart with `type`, `data` and `config`."
  [type data &opt config]
  (def conf (cond-> (merge default-config {:type type}) config (merge config)))
  (:render (make Chart :config conf :data data)))
