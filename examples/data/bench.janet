(use gp/data/navigation gp/data/schema)

(use /examples/tools)

(print "Starting")

(var s (os/clock))
(defn reset [] (set s (os/clock)))

(def db
  (init-db 50))

(printf "Initialized in: %s" (precise-time (- (os/clock) s)))

(print
  ((=> :clients (>map-get :projects)
       (>map values) flatten (>map-get :tasks)
       (>map values) flatten length) db) " tasks in DB")

(print "flatten ")
(bench 10
       ((=> :clients (>map-get :projects)
            (>map values) flatten (>map-get :tasks)
            (>map values) flatten (>map-get :name) flatten) db))


(print "flatvals ")
(bench 10
       ((=> :clients (>map-get :projects)
            >flatvals (>map-get :tasks) >flatvals (>map-get :name)) db))


(print "valflatname ")
(defn valflatname [base]
  (def res @[])
  (loop [t :in base] (array/push res ;(map |($ :name) (values t))))
  res)

(bench 10
       ((=> :clients (>map-get :projects)
            >flatvals (>map-get :tasks) valflatname) db))

(reset)
(prin "Jimage with the size " (brshift (length (marshal db)) 20) "MB ")

(printf "was generated in %s" (precise-time (- (os/clock) s)))
