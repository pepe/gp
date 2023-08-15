(use gp/data/navigation gp/data/schema)

(use /examples/tools)

(print "Starting")

(var s (os/clock))
(defn reset [] (set s (os/clock)))

(def db
  (init-db 100))

(printf "Initialized in: %s" (precise-time (- (os/clock) s)))

(print
  ((=> :clients (in-all :projects)
       (all-by values) flatten (in-all :tasks)
       (all-by values) flatten length) db) " tasks in DB")

(print "flatten ")
(bench 10
       ((=> :clients (in-all :projects)
            (all-by values) flatten (in-all :tasks)
            (all-by values) flatten (in-all :name) flatten) db))


(print "flatvals ")
(bench 10
       ((=> :clients (in-all :projects)
            flatvals (in-all :tasks) flatvals (in-all :name)) db))


(print "valflatname ")
(defn valflatname [base]
  (def res @[])
  (loop [t :in base] (array/push res ;(map |($ :name) (values t))))
  res)

(bench 10
       ((=> :clients (in-all :projects)
            flatvals (in-all :tasks) valflatname) db))

(reset)
(prin "Jimage with the size " (brshift (length (marshal db)) 20) "MB ")

(printf "was generated in %s" (precise-time (- (os/clock) s)))
