(use spork/test spork/misc)
(use ../gp/data/intel)
(start-suite "Inteligence documentation")
(assert-docs "../gp/data/intel")
(end-suite)

(start-suite "String tools")
(assert (deep= @["a" "b"] ((splitter "\n") "a\nb")))
(assert (deep= "{\"name\": \"test\", \"amount\": \"666\"}"
               (slurp-trim "./test/test.json")))
(end-suite)
(start-suite "Exporters")
(assert (= "a,b,c" (jdn->csv-record ["a" "b" "c"])))
(assert (deep= @["a" "b" "c"] (csv-record->jdn "a,b,c")))
(setdyn *separator* ";")
(assert (= "a;b;c" (jdn->csv-record ["a" "b" "c"])))
(assert (deep= @["a" "b" "c"] (csv-record->jdn "a;b;c")))
(assert (deep= @["a" "b" "c"] (csv-record->jdn "a;b;c\n")))
(end-suite)
(start-suite "Loaders")
(assert (deep= @{"amount" "666" "name" "test"}
               (json-file->jdn "./test/test.json")))
(assert (deep= @[@{"amount" "666" "name" "test"}
                 @{"amount" "777" "name" "testy"}]
               (jsons-file->jdn "./test/tests.json")))
(end-suite)
