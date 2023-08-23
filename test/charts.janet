(use spork/test spork/misc judge)

(start-suite "DDocumentation")
(assert-docs "../gp/charts")
(end-suite)

(import ../gp/charts)

(test (make charts/Chart) @{})

(test (:render (charts/make-bar []))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g {:class "chart bar"}]])


(test (:render (charts/make-bar [1]))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 1000 :width 1000 :x 0 :y 0}]]])


(test (:render (charts/make-bar [-1 1 2 3]))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 250 :width 250 :x 0 :y 750}]
        [:rect
         {:height 250 :width 250 :x 250 :y 500}]
        [:rect
         {:height 500 :width 250 :x 500 :y 250}]
        [:rect
         {:height 750 :width 250 :x 750 :y 0}]]])

(test (:render (charts/make-bar [-1 1 2 3]))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 250 :width 250 :x 0 :y 750}]
        [:rect
         {:height 250 :width 250 :x 250 :y 500}]
        [:rect
         {:height 500 :width 250 :x 500 :y 250}]
        [:rect
         {:height 750 :width 250 :x 750 :y 0}]]])

(test (:render (charts/make-bar [1] {:axis true}))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 1000 :width 1000 :x 0 :y 0}]]
       [:g
        {:class "axis"}
        [:line {:x1 0 :x2 0 :y1 0 :y2 1000}]
        [:line
         {:x1 0 :x2 1000 :y1 1000 :y2 991}]]])

(test (:render (charts/make-bar [1 2 3 4]))
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart bar"}
        [:rect
         {:height 250 :width 250 :x 0 :y 750}]
        [:rect
         {:height 500 :width 250 :x 250 :y 500}]
        [:rect
         {:height 750 :width 250 :x 500 :y 250}]
        [:rect
         {:height 1000 :width 250 :x 750 :y 0}]]])
