(use spork/test)

(start-suite "docs")
(assert-docs "../gp/gen")
(assert-docs "../gp/gen/project")
(end-suite)
