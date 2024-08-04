(when (= :windows (os/which))
  (eprint "Term is not supported on windows")
  (os/exit 0)) 

(use spork/test)
(use /gp/tui)

(start-suite "TUI documentation")
(assert-docs "../gp/tui")
(end-suite)
