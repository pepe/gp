(use spork/htmlgen)

(defn render
  "Renders chart."
  [chart]
  (def {:height height :width width :margin margin} (chart :config))
  (def res
    @[:svg (merge (get-in chart [:config :svg])
                  {:width width :height height})])
  (when-let [d (chart :data)
             w (/ (- width (* 2 margin)) (length d))
             h (- height (* 2 margin))
             mx (max 0 ;d)
             mn (min 0 ;d)
             ex (- mx mn)]
    (loop [[i p] :pairs d :let [ih (* (/ p ex) h)
                                x (+ margin (* i w))
                                y (- height (+ margin ih))]]
      (array/push res [:rect {:x x :y y :width w :height ih}])))
  (freeze res))
# (seq [[i d] :pairs (chart :data)] [:rect @{:x 10 :y 10 :width 980 :height 980}])

(def Chart
  "Prototype for a Chart."
  @{:config @{:margin 0 :width 1000 :height 1000
              :svg @{:version "1.1" :xmlns "http://www.w3.org/2000/svg"}}
    :data ()
    :render render})
