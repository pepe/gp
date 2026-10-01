(use /gp/utils)

(defn main
  "Installs gp, then runs tests on whole project, or optionaly `file`"
  [_ &opt filename]
  (def test
    (if filename
      @["janet" filename]
      @[(script "janet-pm") "test"]))
  # Tests import the installed gp, so every change is installed first.
  # Arrays, as %j prints a tuple in parentheses, which would be a call.
  (def install-then-test
    (string/format "(os/execute %j :px) (os/execute %j :p)"
                   @[(script "janet-pm") "install"] test))
  (watch-spawn '(* (+ "gp" "cjanet" "test") (thru ".janet") -1)
               ["janet" "-e" install-then-test] true))
