(use spork/test spork/misc judge)

(start-suite "DDocumentation")
(assert-docs "../gp/charts")
(end-suite)

(import ../gp/charts)
(var chart (make charts/Chart))
(test chart @{})

(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}])

(set (chart :data) [1])
(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart"}
        [:rect
         {:height 1000 :width 1000 :x 0 :y 0}]]])

(set (chart :data) [-1 1 2 3])
(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart"}
        [:rect
         {:height 250 :width 250 :x 0 :y 750}]
        [:rect
         {:height 250 :width 250 :x 250 :y 500}]
        [:rect
         {:height 500 :width 250 :x 500 :y 250}]
        [:rect
         {:height 750 :width 250 :x 750 :y 0}]]])

(set (chart :data) [1])
(update chart :config put :margin 10)
(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart"}
        [:rect
         {:height 980 :width 980 :x 10 :y 10}]]])

(set (chart :data) [-1 1 2 3])
(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "chart"}
        [:rect
         {:height 230 :width 245 :x 10 :y 760}]
        [:rect
         {:height 230 :width 245 :x 255 :y 530}]
        [:rect
         {:height 460 :width 245 :x 500 :y 300}]
        [:rect
         {:height 690 :width 245 :x 745 :y 70}]]])

(update chart :config merge-into {:margin 10 :axis {:stroke "black"}})
(set (chart :data) [1])
(test (:render chart)
      [:svg
       {:height 1000
        :version "1.1"
        :width 1000
        :xmlns "http://www.w3.org/2000/svg"}
       [:g
        {:class "axis" :stroke "black"}
        [:line {:x1 10 :x2 10 :y1 0 :y2 1000}]
        [:line {:x1 0 :x2 990 :y1 990 :y2 990}]]
       [:g
        {:class "chart"}
        [:rect
         {:height 980 :width 980 :x 10 :y 10}]]])
