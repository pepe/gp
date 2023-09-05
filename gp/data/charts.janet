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
  (array/concat res
                [[:line {:x1 0 :y1 0 :x2 0 :y2 h}]
                 [:line {:x1 0 :y1 h :x2 w :y2 h}]])
  (when-let [u (chart :unit)
             {:data-length dl :item-width iw :item-height ih
              :data-max dmx :data-min dmn :extreme ex :zero zo} chart
             l (/ h 100)]
    (loop [dy :range [(- h zo) zo (* u ih)]]
      (array/push res [:line {:x1 0 :y1 dy :x2 l :y2 dy}]))
    (loop [dx :down [w 0 (* u iw)]]
      (array/push res
                  [:line {:x1 dx :y1 (- h l) :x2 dx :y2 h}])))
  (array/push (chart :content) res)
  chart)

(defn- _process
  "Processes data and sets instance fields."
  [chart]
  (if-not (chart :processed)
    (let [{:d d :height height :width width} chart
          dl (length d) dmn (min 0 ;d) dmx (max 0 ;d)
          ex (- dmx dmn) ih (/ height ex)]
      (merge-into chart
                  {:processed true
                   :data-length dl :data-max dmx :data-min dmn
                   :extreme ex :item-width (/ width dl) :item-height ih
                   :zero (- height (* -1 dmn ih))}))
    chart))

(defn- _bar
  "Renders bar chart"
  [chart & config]
  (:config chart config)

  (if (chart :content)
    (array/push
      (chart :content)
      (do-def
        res @[:g {:class "chart bar"}]
        (if-let [d ((:process chart) :d)]
          (let [{:d d :height height :width width
                 :data-length dl :item-width iw :item-height ih
                 :data-max dmx :data-min dmn :extreme ex :zero zo} chart]
            (loop [[i p] :pairs d
                   :let [ph (math/abs (* p ih))
                         x (* i iw)
                         y (if (pos? p) (- zo ph) zo)]]
              (array/push res [:rect {:x x :y y :width iw :height ph}])))
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
    :process _process
    :render
    (fn _render
      [chart]
      (freeze (chart :content)))})
