(use /gp/utils)

(watch-spawn '(* (+ "gp" "cjanet" "test") (thru ".janet") -1)
             ["janet-pm.bat" "test"] true)
