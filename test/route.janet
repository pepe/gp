(use spork/test spork/misc)
(use ../gp/route)

(start-suite "Route documentation")
(assert-docs "../gp/route")
(end-suite)
(start-suite "router")

(def config "Routes' config for all tests"
  {"/" :root
   "/home/:id" :home
   "/real-thing.json" :real-thing
   "/involved/:id/example/:example-id/detail/:detail-id" :involved})

(assert
  (compile-routes config)
  "compile routes")

(assert
  (all |(= :core/peg (type $))
       (map first (compile-routes config)))
  "items last pegs")

(assert
  (deep=
    (sort (map last (compile-routes config)))
    (sort @[:home :real-thing :involved :root]))
  "all values")

(assert
  (deep= (lookup (compile-routes config) "/home/3")
         [:home @{:id "3"}])
  "lookup home")

(assert
  (deep= (lookup (compile-routes config) "/")
         [:root @{}])
  "lookup root")

(assert
  (deep= (lookup (compile-routes config) "/real-thing.json")
         [:real-thing @{}])
  "lookup real-thing")

(assert
  (empty? (lookup (compile-routes config) "/home/"))
  "lookup wrong")

(assert (router config) "router")

(assert
  (deep=
    ((router config) "/")
    [:root @{}])
  "router root")

(assert
  (deep=
    ((router config) "/home/3")
    [:home @{:id "3"}])
  "router home")

(assert
  (deep= ((router config) "/real-thing.json") [:real-thing @{}])
  "router json")

(assert
  (empty? ((router config) "home"))
  "wrong route")


(assert (resolver config) "resolver")

(assert (= ((resolver config) :root) "/") "resolve home")

(assert
  (=
    ((resolver config) :home @{:id 3})
    "/home/3")
  "resolve home")

(assert
  (=
    ((resolver config) :involved @{:id 1 :example-id 2 :detail-id 3})
    "/involved/1/example/2/detail/3"))

(end-suite)
