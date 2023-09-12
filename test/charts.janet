(use spork/test spork/misc)

(start-suite "Documentation")
(assert-docs "../gp/data/charts")
(end-suite)

(import ../gp/net/http)
(import ../gp/data/charts)

(assert (deep= (make charts/Chart) @{}))

(assert-error "No content to construct the chart in"
              (:bar (make charts/Chart) :d [1]))

(assert (= (:render (:svg (make charts/Chart)))
           [:svg
            {:version "1.1"
             :xmlns "http://www.w3.org/2000/svg"}]))

(assert (= (:render (:svg (make charts/Chart) :height 100 :width 100))
           [:svg
            {:height 100
             :width 100
             :version "1.1"
             :xmlns "http://www.w3.org/2000/svg"}]))

(assert (= (:render (:svg (make charts/Chart) :height 100 :width 100))
           [:svg
            {:height 100
             :width 100
             :version "1.1"
             :xmlns "http://www.w3.org/2000/svg"}]))

(assert (= (:render (:svg (make charts/Chart) :height 100 :width 100
                          :viewBox "0 0 100 100"))
           [:svg
            {:height 100
             :version "1.1"
             :viewBox "0 0 100 100"
             :width 100
             :xmlns "http://www.w3.org/2000/svg"}]))

(assert-error "No content to construct the chart in" (:svg (:bar (make charts/Chart))))

(assert (= (:render (:bar (:svg (make charts/Chart) :height 100 :width 100) :d [1]))
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 100 :width 100 :x 0 :y 0}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:bar :d [-1 1 2 3]) :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 25 :width 25 :x 0 :y 75}]
             [:rect {:height 25 :width 25 :x 25 :y 50}]
             [:rect {:height 50 :width 25 :x 50 :y 25}]
             [:rect {:height 75 :width 25 :x 75 :y 0}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:bar :d [1]) :axis :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 100 :width 100 :x 0 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
             [:line {:x1 0 :x2 100 :y1 100 :y2 100}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:bar :d [1])
               (:axis :unit 1) :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 100 :width 100 :x 0 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
             [:line {:x1 0 :x2 100 :y1 100 :y2 100}]
             [:symbol {:id "hdot" :width 1 :height 1}
              [:line {:x1 0 :y1 0 :x2 1 :y2 0}]]
             [:symbol {:id "vdot" :width 1 :height 1}
              [:line {:x1 0 :y1 0 :x2 0 :y2 1}]]
             [:use {:href "hdot" :x 0 :y 0}]
             [:use {:href "vdot" :x 100 :y 99}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:bar :d [1])
               (:axis :unit 0.5) :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect
              {:height 100 :width 100 :x 0 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
             [:line {:x1 0 :x2 100 :y1 100 :y2 100}]
             [:symbol {:height 1 :id "hdot" :width 1}
              [:line {:x1 0 :x2 1 :y1 0 :y2 0}]]
             [:symbol {:height 1 :id "vdot" :width 1}
              [:line {:x1 0 :x2 0 :y1 0 :y2 1}]]
             [:use {:href "hdot" :x 0 :y 0}]
             [:use {:href "hdot" :x 0 :y 50}]
             [:use {:href "vdot" :x 100 :y 99}]
             [:use {:href "vdot" :x 50 :y 99}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:bar :d [1 2 3 4])
               (:axis :unit 1) :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 25 :width 25 :x 0 :y 75}]
             [:rect {:height 50 :width 25 :x 25 :y 50}]
             [:rect {:height 75 :width 25 :x 50 :y 25}]
             [:rect {:height 100 :width 25 :x 75 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
             [:line {:x1 0 :x2 100 :y1 100 :y2 100}]
             [:symbol {:height 1 :id "hdot" :width 1}
              [:line {:x1 0 :x2 1 :y1 0 :y2 0}]]
             [:symbol {:height 1 :id "vdot" :width 1}
              [:line {:x1 0 :x2 0 :y1 0 :y2 1}]]
             [:use {:href "hdot" :x 0 :y 0}]
             [:use {:href "hdot" :x 0 :y 25}]
             [:use {:href "hdot" :x 0 :y 50}]
             [:use {:href "hdot" :x 0 :y 75}]
             [:use {:href "vdot" :x 100 :y 99}]
             [:use {:href "vdot" :x 75 :y 99}]
             [:use {:href "vdot" :x 50 :y 99}]
             [:use {:href "vdot" :x 25 :y 99}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 1000 :width 1000)
               (:bar :d [1 2 3 4])
               (:axis :unit 1) :render)
           [:svg
            {:height 1000 :version "1.1" :width 1000
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 250 :width 250 :x 0 :y 750}]
             [:rect {:height 500 :width 250 :x 250 :y 500}]
             [:rect {:height 750 :width 250 :x 500 :y 250}]
             [:rect {:height 1000 :width 250 :x 750 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 1000}]
             [:line {:x1 0 :x2 1000 :y1 1000 :y2 1000}]
             [:symbol {:height 1 :id "hdot" :width 10}
              [:line {:x1 0 :x2 10 :y1 0 :y2 0}]]
             [:symbol {:height 10 :id "vdot" :width 1}
              [:line {:x1 0 :x2 0 :y1 0 :y2 10}]]
             [:use {:href "hdot" :x 0 :y 0}]
             [:use {:href "hdot" :x 0 :y 250}]
             [:use {:href "hdot" :x 0 :y 500}]
             [:use {:href "hdot" :x 0 :y 750}]
             [:use {:href "vdot" :x 1000 :y 990}]
             [:use {:href "vdot" :x 750 :y 990}]
             [:use {:href "vdot" :x 500 :y 990}]
             [:use {:href "vdot" :x 250 :y 990}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 1000 :width 1000)
               (:bar :d [1 2 3 4])
               (:axis :unit 1 :unit-ratio 0.1) :render)
           [:svg
            {:height 1000 :version "1.1" :width 1000
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart bar"}
             [:rect {:height 250 :width 250 :x 0 :y 750}]
             [:rect {:height 500 :width 250 :x 250 :y 500}]
             [:rect {:height 750 :width 250 :x 500 :y 250}]
             [:rect {:height 1000 :width 250 :x 750 :y 0}]]
            [:g
             {:class "axis"}
             [:line {:x1 0 :x2 0 :y1 0 :y2 1000}]
             [:line {:x1 0 :x2 1000 :y1 1000 :y2 1000}]
             [:symbol {:height 1 :id "hdot" :width 100}
              [:line {:x1 0 :x2 100 :y1 0 :y2 0}]]
             [:symbol {:height 100 :id "vdot" :width 1}
              [:line {:x1 0 :x2 0 :y1 0 :y2 100}]]
             [:use {:href "hdot" :x 0 :y 0}]
             [:use {:href "hdot" :x 0 :y 250}]
             [:use {:href "hdot" :x 0 :y 500}]
             [:use {:href "hdot" :x 0 :y 750}]
             [:use {:href "vdot" :x 1000 :y 900}]
             [:use {:href "vdot" :x 750 :y 900}]
             [:use {:href "vdot" :x 500 :y 900}]
             [:use {:href "vdot" :x 250 :y 900}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:spark :d [1 2 3 4 4])
               :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:g
             {:class "chart spark"}
             [:polyline {:points "0, 75 25, 50 50, 25 75, 0 100, 0"}]
             [:polygon
              {:points "0, 75 25, 50 50, 25 75, 0 100, 0 100, 100 0, 100"}]]]))

(assert (= (-> (make charts/Chart)
               (:svg :height 100 :width 100)
               (:style (http/style [[".chart rect" {:fill :black}]]))
               (:bar :d [1])
               :render)
           [:svg
            {:height 100 :version "1.1" :width 100
             :xmlns "http://www.w3.org/2000/svg"}
            [:style ".chart rect {fill: black;}"]
            [:g
             {:class "chart bar"}
             [:rect {:height 100 :width 100 :x 0 :y 0}]]]))
