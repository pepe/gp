(use spork/math /gp/utils)

(defn init-db
  "Initialise db with tree of size `c`"
  [c]
  (def res @{:clients @{}})
  (var i 0)
  (repeat c
    (def n (string "client" i))
    (put-in res [:clients n] @{:name n :projects @{}})
    (++ i)
    (repeat c
      (def pn (string "project" i))
      (put-in res [:clients n :projects pn] @{:name pn})
      (++ i)
      (repeat c
        (def tn (string "task" i))
        (put-in res [:clients n :projects pn :tasks tn] @{:name pn})
        (++ i))))
  res)

(defn precise-string
  "Returns number `v` as 10 digits precision string."
  [v]
  (string/format "%.10f" v))

(defn duration-from
  "Returns the duration in seconds from `ts` to now."
  [ts]
  (- (os/clock) ts))

(defmacro bench
  ```
  Runs the `body` code `runs` times and prints simple stats.
  Garbage collection is performed after every run.
  ```
  [runs & body]
  (with-syms [r e su ct st l t]
    ~(do
       (var ,su 0)
       (def ,r (array/new ,runs))
       (def ,st (os/clock))
       (repeat ,runs
         (def ,e (os/clock))
         ,;body
         (def ,ct (,duration-from ,e))
         (array/push ,r ,ct)
         (+= ,su ,ct)
         (gccollect))
       (def summary
         [["Elapsed" ,su]
          ["Mean" (/ ,su ,runs)]
          ["Min" (min-of ,r)]
          ["First qrtl" (,quantile ,r 0.25)]
          ["Median" (,median ,r)]
          ["Third qrtl" (,quantile ,r 0.75)]
          ["Max" (max-of ,r)]
          ["StdDev" (,standard-deviation ,r)]
          ["Total" (,duration-from ,st)]])
       (loop [[,l ,t] :in summary]
         (printf "%11s: %10s" ,l (,precise-time ,t))))))
