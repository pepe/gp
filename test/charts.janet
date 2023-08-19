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
                  [:rect {:x 10 :y 10 :width 980 :height 980}]])
          "render with data"))

(let [chart (make charts/Chart)]
  (set (chart :data) [1 2])
  (assert (deep= (:render chart)
                 [:svg {:version "1.1" :width 1000 :height 1000
                        :xmlns "http://www.w3.org/2000/svg"}
                  [:rect {:x 10 :y 500 :width 490 :height 490}]
                  [:rect {:x 500 :y 10 :width 490 :height 980}]])
          "render with 2 data"))
(end-suite)
