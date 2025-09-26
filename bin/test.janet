(use /gp/utils)

(watch-spawn '(* (+ "gp" "cjanet" "test") (thru ".janet") -1)
             [(script "janet-pm") "test"] true)
