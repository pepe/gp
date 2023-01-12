(use spork/test)
(use /build/gp/data/fuzzy)

(start-suite "Fuzzy")

(assert (has-match "s" "as")
        "has-match")

(assert-not (has-match "Z" "as")
            "has not match")

(assert (= -0.015 (score "ss" "ases"))
        "score")

(assert (< 1.875 (score "cos" "crosses"))
        "score")

(assert (= score-min (score "cos" "added"))
        "score-min")

(assert (= score-max (score "cos" "cos"))
        "score-max")

(assert (deep= (positions "s" "has") @[2])
        "positions")

(assert (deep= (positions "as" "has") @[1 2])
        "positions l")

(end-suite)
