(use spork/test)
(import /build/gp/term)

(assert-docs "/build/gp/term")
(start-suite)
(defer (term/shutdown)
  (term/init)
  (assert (> (term/width) 0) "width")
  (assert (> (term/height) 0) "height")
  (def x (math/floor (/ (term/width) 2)))
  (def y (math/floor (/ (term/height) 2)))
  (assert-no-error
    (term/set-cursor x y))
  (assert-no-error
    (term/hide-cursor))
  (assert-no-error
    (term/set-cell x y (chr "a") 0 0))
  (assert-no-error
    (term/print x y 0 0 "Ho ho ho"))
  (assert-no-error
    (term/present))
  (assert-no-error (term/clear))
  (assert term/key-f1 "f1")
  (def e (term/init-event))
  (assert term/poll))
(end-suite)
