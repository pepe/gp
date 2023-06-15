(use spork/test)
(import /gp/screen)
(assert-docs "/gp/screen")
(start-suite "screen")
(comment (screen
           (each i (range (term/height))
             (term/at i i "a"))
           (term/input)))
(end-suite)
