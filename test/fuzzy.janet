(use spork/test spork/math)
(use /build/gp/data/fuzzy)

(start-suite "Fuzzy")

(assert (hasmatch "s" "as")
        "hasmatch")

(assert-not (hasmatch "Z" "as")
            "has not match")

(assert (approx-eq -0.015 (score "ss" "ases"))
        "score low")

(assert (approx-eq 1.875 (score "cos" "crosses"))
        "score hi")

(assert (= math/-inf (score "cos" "added"))
        "score-min")

(assert (= math/inf (score "cos" "cos"))
        "score-max")

(assert (deep= (positions "s" "has") @[2])
        "positions")

(assert (deep= (positions "as" "has") @[1 2])
        "positions l")

(assert (deep= (order-scores "as" @["has" "mass" "ass"])
               @["ass" "has" "mass"]))

(assert (order-scores "it8" (seq [i :range [0 10000]]
                              (string "item" (math/random)))))

(end-suite)
