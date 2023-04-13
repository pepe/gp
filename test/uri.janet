(use spork/test)
(use /gp/net/uri)

(start-suite)
(assert (= (escape "=+%") "%3d%2b%25") "escape")
(assert (= (unescape "%3d%2b%25") "=+%") "unescape")
(def parse-tests [["foo://127.0.0.1"
                   @{:scheme "foo" :host "127.0.0.1" :path "" :raw-path ""}]

                  ["foo://example.com:8042/over%20there?name=fer%20ret#nose"
                   @{:path "/over there" :raw-path "/over%20there" :host "example.com"
                     :fragment "nose" :raw-fragment "nose" :scheme "foo" :port "8042"
                     :raw-query "name=fer%20ret" :query @{"name" "fer ret"}}]

                  ["/over/there?name=ferret#nose"
                   @{:path "/over/there" :raw-path "/over/there"
                     :fragment "nose" :raw-fragment "nose"
                     :raw-query "name=ferret" :query @{"name" "ferret"}}]

                  ["//"
                   @{:raw-path "" :path "" :host ""}]

                  ["/"
                   @{:raw-path "/" :path "/"}]

                  [""
                   @{}]])

(each tc parse-tests
  (assert (deep= (parse (tc 0)) (tc 1)) "parse"))

(let [rng (math/rng (os/time))]
  (loop [i :range [0 1000]]
    (def n (math/rng-int rng 2000))
    (def s (string (os/cryptorand n)))
    (assert (= s (unescape (escape s)))
            "unescape")))

(def parse-query-tests [["" @{}]
                        ["abc=5&%20=" @{"abc" "5" " " ""}]
                        ["a=b" @{"a" "b"}]])

(each tc parse-query-tests
  (assert (deep= (parse-query (tc 0)) (tc 1))
          "parse-query"))
(end-suite)
