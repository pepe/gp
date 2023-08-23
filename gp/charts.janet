(use spork/htmlgen spork/misc)

(defn render
  "Renders chart."
  [chart]
  (def {:height height :width width :margin margin} (chart :config))
  (def content @[])
  (when-let [d (chart :data)
             ld (length d)
             iw (/ (- width (* 2 margin)) ld)
             h (- height (* 2 margin))
             mx (max 0 ;d) mn (min 0 ;d) ex (- mx mn)
             ih (- (/ height ex) (* 2 margin)) zero (- h (* -1 mn ih) (- margin))]

    (def res @[:g {:class "chart"}])
    (loop [[i p] :pairs d :let [ih (math/abs (* p ih))
                                x (+ margin (* i iw))
                                y (math/floor (if (pos? p)
                                                (- zero ih)
                                                zero))]]
      (array/push res [:rect {:x x :y y :width iw :height ih}]))

    (array/push content res)
    (when-let [style (get-in chart [:config :axis])]
      (def res @[:g (merge {:class "axis"} style)])
      (array/push res [:line {:x1 margin :y1 0 :x2 margin :y2 height}])
      (array/push res [:line {:x1 0 :y1 (- height margin)
                              :x2 (- width margin) :y2 (- height margin)}])

      (array/push content res)))
  (freeze [:svg (merge (get-in chart [:config :svg])
                       {:width width :height height}) ;content]))
# (seq [[i d] :pairs (chart :data)] [:rect @{:x 10 :y 10 :width 980 :height 980}])

(def Chart
  "Prototype for a Chart."
  @{:config @{:margin 0 :width 1000 :height 1000
              :svg @{:version "1.1" :xmlns "http://www.w3.org/2000/svg"}}
    :data false
    :render render})
