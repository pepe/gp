(use spork/htmlgen spork/misc)

(defn- _axis
  ```
  Renders optional axis.
  This function is called when you call `:axis` method on chart
  ```
  [chart & config]
  (:config chart config)
  (def {:height h :width w} chart)
  (def res @[:g {:class "axis"}])
  (array/push res [:line {:x1 0 :y1 0 :x2 0 :y2 h}])
  (array/push res [:line {:x1 0 :y1 h :x2 w :y2 h}])

  (if-let [u (chart :unit)] u)
  (array/push (chart :content) res)
  chart)

(defn- _bar
  "Renders bar chart"
  [chart & config]
  (:config chart config)
  (if (chart :content)
    (array/push
      (chart :content)
      (do-def
        res @[:g {:class "chart bar"}]
        (if-let [d (chart :d)]
          (let [{:d d :height height :width width} chart
                data-length (length d) # move to process
                item-width (/ width data-length)
                data-max (max 0 ;d)
                data-min (min 0 ;d)
                extreme (- data-max data-min)
                item-height (/ height extreme)
                zero (- height (* -1 data-min item-height))]
            (loop [[i p] :pairs d
                   :let [ph (math/abs (* p item-height))
                         x (* i item-width)
                         y (if (pos? p) (- zero ph) zero)]]
              (array/push res [:rect {:x x :y y :width item-width :height ph}])))
          (error "No data to chart"))))
    (error "No content to construct the chart in"))
  chart)

(defn- _svg
  "Sets svg chart"
  [chart & config]
  (def tconf (table ;config))
  (merge-into chart tconf)
  (put chart :content
       @[:svg (merge {:version "1.1"
                      :xmlns "http://www.w3.org/2000/svg"}
                     tconf)]))

(def Chart
  "Prototype for a Chart."
  @{:svg _svg
    :bar _bar
    :axis _axis
    :config (fn _config [chart config] (merge-into chart (table ;config)))
    :render
    (fn _render
      [chart]
      (freeze (chart :content)))})
