(use spork/htmlgen spork/misc)

(defn- _axis
  ```
  Renders optional axis.
  This function is called when you call `:axis` method on chart
  ```
  [chart &opt config]
  (def {:height h :width w} chart)
  (def res @[:g {:class "axis"}])
  (array/push res [:line {:x1 0 :y1 0 :x2 0 :y2 h}])
  (array/push res [:line {:x1 0 :y1 h :x2 w :y2 h}])

  (if config
    (def {:unit u} config))
  (array/push (chart :content) res)
  chart)

(defn- _bar
  "Renders bar chart"
  [chart]
  (array/push
    (chart :content)
    (do-def res @[:g {:class "chart bar"}]
            (if-let [d (chart :d)]
              (let [{:d d :height height :width width} chart
                    ld (length d)
                    iw (/ width ld)
                    mx (max 0 ;d) mn (min 0 ;d) ex (- mx mn)
                    ih (/ height ex)
                    zero (- height (* -1 mn ih))]
                (loop [[i p] :pairs d :let [ph (math/abs (* p ih))
                                            x (* i iw)
                                            y (if (pos? p) (- zero ph) zero)]]
                  (array/push res [:rect {:x x :y y :width iw :height ph}])))
              (error "No data to render"))))
  chart)

(defn- set-svg
  "Sets svg chart"
  [chart]
  (merge-into chart {:main :svg :version "1.1" :content @[]
                     :xmlns "http://www.w3.org/2000/svg"
                     :main-attrs [:version :xmlns :width :height]}))

(def Chart
  "Prototype for a Chart."
  @{:svg set-svg
    :bar _bar
    :axis _axis
    :render
    (fn _render
      [chart]
      (freeze [(chart :main)
               (select-keys chart (chart :main-attrs))
               ;(chart :content)]))})
