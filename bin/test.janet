(use /gp/utils)

(defn main
  "Runs tests on whole project, or optionaly `file`"
  [_ &opt filename]
  (def script
    (if filename
      ["janet" filename]
      [(script "janet-pm") "test"]))
  (watch-spawn '(* (+ "gp" "cjanet" "test") (thru ".janet") -1)
               script true))
