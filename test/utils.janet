(use spork/test spork/misc)
(use ../gp/utils)
(start-suite "Documentation")
(assert-docs "../gp/utils")
(end-suite)

(start-suite "Code")
(assert (match (fprotect (error "HOHO"))
          [false (f (fiber? f))] true false))
(assert
  (= "0" (first-capture '(* (to :d) ':d) "abcd0"))
  "first capture")

(assert
  (match (fprotect (error "HOHO"))
    [false (f (fiber? f))]
    (do
      (assert (= (fiber/last-value f) "HOHO"))
      (assert (= (fiber/status f) :error)))
    false)
  "fprotect 2")

(assert (deep= (union @[1 2 3] @[3 4 5]) @[1 2 3 4 5])
        "union")

(assert (deep= (intersect @[1 2 3] @[3 4 5]) @[3])
        "intersect")

(assert peg-grammar
        "peg grammar")

(assert (setup-peg-grammar)
        "setup-peg-grammar")

(assert (deep= (peg/match ~(* :cap-to-crlf :crlf) "hoho\r\n\r\n")
               @["hoho"])
        "peg-grammar 1")

(assert (deep= (peg/match ~(* :toe) "hoho")
               @["hoho"])
        "peg-grammar 2")

(assert (deep= (peg/match ~(* ,(<-: :cry :toe)) "hoho")
               @[@[:cry "hoho"]])
        "peg-grammar 3")

(assert (deep= (peg/match :split "hoho-haha bee_sure data/code love\\hate war|peace")
               @["hoho" "haha" "bee" "sure" "data" "code" "love" "hate" "war" "peace"])
        "peg-grammar 4")

(assert (one-of 1 1 2 3) "one of")

(assert (one-of "hi" "lo" "mine" "hi")
        "one of tuple")

(do
  (setdyn :conn true)
  (define :conn)
  (assert conn "define"))

(end-suite)
