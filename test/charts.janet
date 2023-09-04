(use spork/test spork/misc judge)

(start-suite "Documentation")
(assert-docs "../gp/data/charts")
(end-suite)

(import ../gp/data/charts)

(test (make charts/Chart) @{})

(test-error (:bar (make charts/Chart) :d [1])
            "No content to construct the chart in")

(test (:render (:svg (make charts/Chart)))
      [:svg
       {:version "1.1"
        :xmlns "http://www.w3.org/2000/svg"}])

(test (:render (:svg (make charts/Chart) :height 100 :width 100))
      [:svg
       {:height 100
        :width 100
        :version "1.1"
        :xmlns "http://www.w3.org/2000/svg"}])
(test (:render (:svg (make charts/Chart) :height 100 :width 100))
      [:svg
       {:height 100
        :width 100
        :version "1.1"
        :xmlns "http://www.w3.org/2000/svg"}])

(test (:render (:svg (make charts/Chart) :height 100 :width 100 :viewBox "0 0 100 100"))
      [:svg
       {:height 100
        :version "1.1"
        :viewBox "0 0 100 100"
        :width 100
        :xmlns "http://www.w3.org/2000/svg"}])

(test-error (:svg (:bar (make charts/Chart)))
            "No content to construct the chart in")

(test (:render (:bar (:svg (make charts/Chart) :height 100 :width 100) :d [1]))
      [:svg
       {:height 100
        :version "1.1"
        :width 100
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 100 :width 100 :x 0 :y 0}]]])

(test (-> (make charts/Chart)
          (:svg :height 100 :width 100)
          (:bar :d [-1 1 2 3]) :render)
      [:svg
       {:height 100
        :version "1.1"
        :width 100
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 25 :width 25 :x 0 :y 75}]
        [:rect
         {:height 25 :width 25 :x 25 :y 50}]
        [:rect
         {:height 50 :width 25 :x 50 :y 25}]
        [:rect
         {:height 75 :width 25 :x 75 :y 0}]]])

(test (-> (make charts/Chart)
          (:svg :height 100 :width 100)
          (:bar :d [1]) :axis :render)
      [:svg
       {:height 100
        :version "1.1"
        :width 100
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 100 :width 100 :x 0 :y 0}]]
       [:g
        {:class "axis"}
        [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
        [:line {:x1 0 :x2 100 :y1 100 :y2 100}]]])

(comment
  (test (-> (make charts/Chart)
            (:svg :height 100 :width 100)
            (:bar :d [1])
            (:axis {:unit 1}) :render)
        [:svg
         {:height 100
          :version "1.1"
          :width 100
          :xmlns "http://www.w3.org/2000/svg"}
         [:g
          {:class "chart bar"}
          [:rect
           {:height 100 :width 100 :x 0 :y 0}]]
         [:g
          {:class "axis"}
          [:line {:x1 0 :x2 0 :y1 0 :y2 100}]
          [:line {:x1 0 :x2 100 :y1 100 :y2 100}]
          [:line {:x1 0 :y1 0 :x2 1 :y2 0}]
          [:line {:x1 100 :y1 99 :x2 100 :y2 100}]]]))
