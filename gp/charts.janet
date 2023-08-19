(use spork/htmlgen)

(defn render
  "Renders chart."
  [chart]
  (def {:height height :width width :margin margin} (chart :config))
  (def res
    @[:svg {:version "1.1" :width width :height height
            :xmlns "http://www.w3.org/2000/svg"}])
  (when-let [d (chart :data)
             w (/ (- width (* 2 margin)) (length d))
             h (- height (* 2 margin))
             m (max ;d)]
    (loop [[i p] :pairs d :let [ih (* (/ p m) h)]]
      (array/push res
                  [:rect {:x (+ margin (* i w)) :y (- height ( + margin ih))
                          :width w :height ih}])))
  (freeze res))
# (seq [[i d] :pairs (chart :data)] [:rect @{:x 10 :y 10 :width 980 :height 980}])

(def Chart
  "Prototype for a Chart."
  @{:config @{:margin 10 :width 1000 :height 1000}
    :data ()
    :render render})
