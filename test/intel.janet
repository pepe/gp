(use spork/test spork/misc)
(use ../gp/data/intel)
(start-suite "Inteligence documentation")
(assert-docs "../gp/data/intel")
(end-suite)

(start-suite "String tools")
(assert (deep= @["a" "b"] ((splitter "\n") "a\nb")))
(assert (slurp-trim "./test/test.json"))
(end-suite)
(start-suite "Loaders")
(assert (deep= @{"amount" "666" "name" "test"}
               (json-file->jdn "./test/test.json")))
(assert (deep= @[@{"amount" "666" "name" "test"}
                 @{"amount" "777" "name" "testy"}]
               (jsons-file->jdn "./test/tests.json")))
(end-suite)
