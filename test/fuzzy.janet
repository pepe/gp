(use spork/test)
(use /build/gp/data/fuzzy)

(start-suite "Fuzzy")

(assert (hasmatch "s" "as")
        "hasmatch")

(assert-not (hasmatch "Z" "as")
            "has not match")

(assert (= -0.015 (score "ss" "ases"))
        "score low")

(assert (< 1.875 (score "cos" "crosses"))
        "score hi")

(assert (= math/-inf (score "cos" "added"))
        "score-min")

(assert (= math/inf (score "cos" "cos"))
        "score-max")

(assert (deep= (positions "s" "has") @[2])
        "positions")

(assert (deep= (positions "as" "has") @[1 2])
        "positions l")

(end-suite)
