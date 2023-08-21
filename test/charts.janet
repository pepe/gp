(use spork/test spork/misc)

(start-suite "DDocumentation")
(assert-docs "../gp/charts")
(end-suite)

(import ../gp/charts)
(start-suite "Basics")
(assert (make charts/Chart) "make Chart")
(assert (deep= (:render (make charts/Chart))
               [:svg {:version "1.1" :width 1000 :height 1000
                      :xmlns "http://www.w3.org/2000/svg"}])
        "render Chart")

(let [chart (make charts/Chart)]
  (set (chart :data) [1])
  (assert (deep= (:render chart)
                 [:svg {:version "1.1" :width 1000 :height 1000
                        :xmlns "http://www.w3.org/2000/svg"}
                  [:g [:rect {:x 0 :y 0 :width 1000 :height 1000}]]])
          "render with data"))

(let [chart (make charts/Chart)]
  (set (chart :data) [1 2])
  (assert (deep= (:render chart)
                 [:svg {:version "1.1" :width 1000 :height 1000
                        :xmlns "http://www.w3.org/2000/svg"}
                  [:g
                   [:rect {:x 0 :y 500 :width 500 :height 500}]
                   [:rect {:x 500 :y 0 :width 500 :height 1000}]]])
          "render with 2 data"))

(let [chart (make charts/Chart)]
  (set (chart :data) [-1 3])
  (assert (deep= (:render chart)
                 [:svg {:version "1.1" :width 1000 :height 1000
                        :xmlns "http://www.w3.org/2000/svg"}
                  [:g
                   [:rect {:height 250 :width 500 :x 0 :y 750}]
                   [:rect {:height 750 :width 500 :x 500 :y 0}]]])
          "render with 2 data negative"))

(end-suite)
