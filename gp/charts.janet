(use spork/htmlgen)

(defn render
  "Renders chart."
  [chart]
  (def {:height height :width width :margin margin} (chart :config))
  (def content @[])
  (when-let [d (chart :data)
             iw (/ (- width (* 2 margin)) (length d))
             h (- height (* 2 margin))
             mx (max 0 ;d) mn (min 0 ;d) ex (- mx mn)
             ih (/ height ex) zero (- h (* -1 mn ih))]
    (def res @[:g])
    (loop [[i p] :pairs d :let [ih (math/abs (* p ih))
                                x (+ margin (* i iw))
                                y (math/floor (if (pos? p)
                                                (- zero (+ margin ih))
                                                zero))]]
      (array/push res [:rect {:x x :y y :width iw :height ih}]))
    (array/push content res))
  (freeze [:svg (merge (get-in chart [:config :svg])
                       {:width width :height height}) ;content]))
# (seq [[i d] :pairs (chart :data)] [:rect @{:x 10 :y 10 :width 980 :height 980}])

(def Chart
  "Prototype for a Chart."
  @{:config @{:margin 0 :width 1000 :height 1000
              :svg @{:version "1.1" :xmlns "http://www.w3.org/2000/svg"}}
    :data false
    :render render})
