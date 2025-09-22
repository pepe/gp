(use /gp/utils)

(watch-exec '(* (+ "gp" "cjanet" "test") (thru ".janet") -1)
            ["janet-pm.bat" "test"] true)
