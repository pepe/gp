(use spork/test spork/misc)
(import ../gp/net/server)
(use ../gp/net/http)
(start-suite "Documentation")
(assert-docs "../gp/net/http")
(end-suite)

(def request (slurp "./test/request"))
(start-suite "On connection")
(assert (function? (on-connection identity)) "handler function")
(assert (match (protect (on-connection {}))
          [false "Handler is not valid"] true
          false) "wrong type handler")
(end-suite)

(start-suite "Supervisor")
(ev/spawn
  (def sc (ev/chan))
  (server/start sc "localhost" 8000)
  (supervisor sc (on-connection (fn [req] "Hello"))))
(ev/sleep 0.001)
(def w (net/connect "localhost" 8000))
(net/write w request)
(ev/sleep 0.001)
(assert (deep= @"Hello" (net/read w 5)) "Http response")
(end-suite)

(start-suite "Custom rule")
(var res nil)
(ev/spawn
  (def sc (ev/chan))
  (server/start sc "localhost" 8001)
  (supervisor sc
              (on-connection (fn [req] (ev/give-supervisor :product 10) "Hello"))
              [:product val] (set res val)))
(ev/sleep 0.001)

(def w (net/connect "localhost" 8001))
(net/write w request)
(ev/read w 1)

(assert (= res 10) "supervisor product")
(end-suite)

(start-suite "Server")
(defn handler [req] "Hello")
(assert (= :core/channel
           (type (server handler "localhost" 8002))) "returns channel")
(ev/sleep 0.001)

(def w (net/connect "localhost" 8002))
(net/write w request)
(ev/sleep 0.001)

(assert (deep= @"Hello" (net/read w 5)) "Http response")

(var res nil)
(server
  (fn [req] (ev/give-supervisor :product 10) "Hello")
  "localhost" 8003
  [:product val] (set res val))
(ev/sleep 0.001)

(def w (net/connect "localhost" 8003))
(net/write w request)
(ev/sleep 0.001)

(assert (= res 10) "server product")
(end-suite)

(start-suite "Utils")
(assert (not (nil? (coerce-fn :home))) "coerce")
(assert (function? (coerce-fn :home)) "coerce to function")
(assert (= (url-path request) "/?a=b") "url-path")
(assert (closed-err? "Connection reset by peer") "closed? peer")
(assert (closed-err? "stream is closed") "closed? stream")
(end-suite)

(start-suite "Response")
(assert (deep= (http {:status 200 :body "Success"})
               @"HTTP/1.1 200 OK\r\nContent-Length: 7\r\nContent-Type: text/plain\r\n\r\nSuccess")
        "http response")
(assert
  (deep= (success "Success")
         @"HTTP/1.1 200 OK\r\nContent-Length: 7\r\nContent-Type: text/plain\r\n\r\nSuccess")
  "success response")
(assert
  (deep= (no-content "No Content")
         @"HTTP/1.1 204 No Content\r\nContent-Length: 10\r\nContent-Type: text/plain\r\n\r\nNo Content")
  "no content response")
(assert
  (deep= (created "Created")
         @"HTTP/1.1 201 Created\r\nContent-Length: 7\r\nContent-Type: text/plain\r\n\r\nCreated")
  "created response")
(assert
  (deep= (bad-request "Bad request")
         @"HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nContent-Type: text/plain\r\n\r\nBad request")
  "bad request response")
(assert
  (deep= (not-authorized "Not authorized")
         @"HTTP/1.1 401 Unauthorized\r\nContent-Length: 14\r\nContent-Type: text/plain\r\n\r\nNot authorized")
  "not authorized response")
(assert
  (deep= (not-found "Not found")
         @"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nContent-Type: text/plain\r\n\r\nNot found")
  "not found response")
(assert
  (deep= (not-supported "Not supported")
         @"HTTP/1.1 415 Unsupported Media Type\r\nContent-Length: 13\r\nContent-Type: text/plain\r\n\r\nNot supported")
  "not supported response")
(assert
  (deep= (method-not-allowed "Not allowed")
         @"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 11\r\nContent-Type: text/plain\r\n\r\nNot allowed")
  "method not allowed response")
(assert
  (deep= (internal-server-error "Internal server error")
         @"HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\nContent-Type: text/plain\r\n\r\nInternal server error")
  "internal server error response")
(assert
  (deep= (not-implemented "Not implemented")
         @"HTTP/1.1 501 Not Implemented\r\nContent-Length: 15\r\nContent-Type: text/plain\r\n\r\nNot implemented")
  "not implemented response")
(assert
  (deep= (found "/")
         @"HTTP/1.1 302 Found\r\nLocation: /\r\nContent-Length: 0\r\n\r\n")
  "found")
(assert
  (deep= (see-other "/")
         @"HTTP/1.1 303 See Other\r\nLocation: /\r\nContent-Length: 0\r\n\r\n")
  "see other")
(assert
  (deep= (switching-protocols "s3pPLMBiTxaQ9kYGzzhZRbK+xOodeep=")
         @"HTTP/1.1 101 Switching Protocols\r\nContent-Length: 0\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOodeep=\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nContent-Type: text/plain\r\n\r\n"))

(assert
  (= (content-type ".json") {"Content-Type" "application/json; charset=UTF-8"}) "content type")
(assert
  (= (content-type ".json" "ASCII") {"Content-Type" "application/json; charset=ASCII"}) "content type charser")
(assert
  (= (content-type ".jpg") {"Content-Type" "image/jpeg"}) "content type wo charset")

(assert
  (= (freeze (->json {"a" "b"})) `{"a":"b"}`) "->json")

(setdyn :templates "/test")
(assert
  (= (string/trim (page index {})) "<div>index</div>"))

(assert
  (= (string/trim (page nested/index {})) "<div>index</div>"))

(assert
  (= (string/trim (page* "index" {})) "<div>index</div>"))

(assert
  (deep= (cookie "some" "value")
         @{"Set-Cookie" @{"some" "value"}})
  "cookie")

(assert
  (deep= (cookie "other" "value"
                 @{"Set-Cookie" @{"some" "value"}})
         @{"Set-Cookie"
           @{"some" "value"
             "other" "value"}})
  "add more cookies")
(assert (deep= (http {:status 200 :body "Success" :headers (cookie "some" "value")})
               @"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nSet-Cookie: some=value\r\nContent-Length: 7\r\n\r\nSuccess")
        "http response with cookie")
(assert (deep= (http {:status 200
                      :body "Success"
                      :headers (cookie "other" "value"
                                       (cookie "some" "value"))})
               @"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nSet-Cookie: some=value\r\nSet-Cookie: other=value\r\nContent-Length: 7\r\n\r\nSuccess")
        "http response with more cookies")
(assert (deep= (http {:status 200
                      :body "Success"
                      :headers (cookie "other" 10
                                       @{"Set-Cookie" @{"some" "value"}})})
               @"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nSet-Cookie: some=value\r\nSet-Cookie: other=10\r\nContent-Length: 7\r\n\r\nSuccess")
        "http response with more cookies")

(assert (= (tag "h4" "Header 4" {:class "important" :tabindex 3})
           `<h4 class="important" tabindex="3">Header 4</h4>`)
        "tag")
(assert (= (etag "button" {:class "important"})
           `<button class="important"></button>`)
        "etag")
(assert (= (capture-stdout (ptag "h4" "Header 4" {:class "important"}))
           [nil `<h4 class="important">Header 4</h4>`])
        "ptag")
(assert (= (capture-stdout (petag "button" {:class "important"}))
           [nil `<button class="important"></button>`])
        "ptag")
(do
  (def [out in] (os/pipe))
  ((chunked-http {:status 200 :body (coro (each c ["Some" "Chunked" "Success"] (yield c)))}) in)
  (assert (deep= (ev/read out 512)
                 @"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/plain\r\n\r\n4\r\nSome\r\n7\r\nChunked\r\n7\r\nSuccess\r\n0\r\n\r\n")
          "chunked response"))
(end-suite)

(start-suite "Middleware")
(assert
  (deep= ((parser identity) request)
         @{:headers
           @{"User-Agent" "curl/7.75.0"
             "Host" "localhost:8888"
             "Accept" "*/*"}
           :body ""
           :uri "/"
           :method "GET"
           :http-version "1.1"
           :query-string "a=b"})
  "parse request")

(assert
  (not (nil? (drive {"/" :home :not-found :not-found})))
  "creates router middleware")
(assert
  (function? (drive {"/" :home :not-found :not-found}))
  "creates router function")
(assert
  (= ((drive {"/" :home :not-found :not-found}) (parse-request request)) :home)
  "routes to home")
(assert
  (= ((drive {"/" :home :not-found :not-found})
       (parse-request (string/replace "?a=b" "not-found" request))) :not-found)
  "routes to not-found")

(assert
  (not (nil? (json->body identity)))
  "creates json to body middleware")
(assert
  (function? (json->body identity))
  "creates function")
(assert
  (deep= ((json->body identity) @{:body "{\"a\": 1}"})
         @{:body @{"a" 1}})
  "decodes body")

(assert
  (not (nil? (guard-methods identity "GET")))
  "creates method guard middleware")
(assert
  (function? (guard-methods identity "GET"))
  "creates method guard function")
(assert
  (deep= ((guard-methods identity "GET") @{:method "GET"})
         @{:method "GET"})
  "does nothing on right method")
(assert
  (deep= ((guard-methods identity "GET" "POST") @{:method "GET"})
         @{:method "GET"})
  "does nothing on one of the right methods")
(assert
  (deep= ((guard-methods identity "GET") @{:method "POST"})
         @"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 46\r\nContent-Type: text/plain\r\n\r\nMethod 'POST' is not supported. Please use GET")
  "responses with not allowed on wrong method")

(assert
  (dispatch @{"GET" :home})
  "creates dispatch middleware")
(assert
  (function? (dispatch @{"GET" :home}))
  "creates function")
(assert
  (deep= ((dispatch @{"GET" :home}) @{:method "GET"})
         :home)
  "returns the right value on  method")
(assert
  (deep= ((dispatch @{"GET" :home}) @{:method "POST"})
         @"HTTP/1.1 501 Not Implemented\r\nContent-Length: 46\r\nContent-Type: text/plain\r\n\r\nMethod POST is not implemented, please use GET")
  "responses with not implemented on wrong method")

(assert
  (not (nil? (typed @{"text/html" :html
                      "text/csv" :csv})))
  "created typed middleware")
(assert
  (function? (typed @{"text/html" :html
                      ".csv" :csv}))
  "created typed middleware")
(assert
  (deep= ((typed @{".html" :html
                   ".csv" :csv})
           @{:headers {"Accept" "text/csv"}})
         :csv)
  "returns right value for the mime type")
(assert
  (deep= ((typed @{".html" :html
                   ".csv" :csv})
           @{:headers {"Accept" "text/xml"}})
         @"HTTP/1.1 415 Unsupported Media Type\r\nContent-Length: 73\r\nContent-Type: text/plain\r\n\r\nMedia '.xml' is not supported, please use one of 'text/html', 'text/csv'.")
  "returns unsuported the mime type")

(assert
  (not (nil? (guard-mime identity ".json")))
  "creates mime guarding middleware")
(assert
  (function? (guard-mime identity ".json"))
  "creates mime guarding function")
(assert
  (deep= ((guard-mime identity ".json")
           @{:headers {"Accept" "application/json"}})
         @{:headers {"Accept" "application/json"}})
  "does nothing on json content type")
(assert
  (deep= ((guard-mime identity ".json") @{:headers {"Accept" "*/*"}})
         @{:headers {"Accept" "*/*"}})
  "does nothing on all content type")
(assert
  (deep= ((guard-mime identity ".json") @{:headers {"Accept" "text/html"}})
         @"HTTP/1.1 415 Unsupported Media Type\r\nContent-Length: 74\r\nContent-Type: text/plain\r\n\r\nMedia 'text/html' is not supported, please use 'application/json' or '*/*'")
  "responses with not supported on wrong content type")

(assert
  (not (nil? (query-params identity)))
  "creates query-params middleware")
(assert
  (= (type (query-params identity)) :function)
  "creates function")
(assert
  (deep= ((query-params identity) @{:query-string "id=1&name=pepe"})
         @{:query-params @{"id" "1" "name" "pepe"}
           :query-string "id=1&name=pepe"})
  "parses query string into table")
(assert
  (deep= ((query-params identity) @{:query-string "id1namepepe"})
         @"HTTP/1.1 400 Bad Request\r\nContent-Length: 32\r\nContent-Type: text/plain\r\n\r\nQuery params have invalid format")
  "does not parse wrong params")

(assert
  (not (nil? (journal identity)))
  "creates journal middleware")
(assert
  (= (type (journal identity)) :function)
  "creates journal function")
(assert
  (string/has-prefix?
    "HTTP/1.1 200 GET /?a=b in "
    ((capture-stderr ((journal success)
                       @{:uri "/" :method "GET" :query-string "a=b"})) 1))
  "prints the log")
(assert
  (peg/match
    '(* "HTTP/1.1 200 GET /?a=b in " (some (+ :d ".")) (+ "u" "m" "") "s, "
        (+ "inf" (some (+ :d "."))) "reqs/s\n" -1)
    ((capture-stderr ((journal success)
                       @{:uri "/" :method "GET" :query-string "a=b"})) 1))
  "prints the log peg")
(assert
  (with-dyns [:out @""]
    (deep= @"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Type: text/plain\r\n\r\nOK"
           (suppress-stderr ((journal (fn [_] (success)))
                              @{:uri "/" :method "GET" :query-string "a=b"}))))
  "returns the response")

(assert
  (not (nil? (static "examples/public/" "index.htm")))
  "creates query-params middleware")
(assert
  (function? (static "examples/public/" "index.htm"))
  "creates function")
(def index (slurp "test/public/index.htm"))
(assert
  (deep= ((static "test/public/" "index.htm") @{:uri "/"})
         (buffer "HTTP/1.1 200 OK\r\nContent-Length: " (length index)
                 "\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n" index))
  "serves static file")

(assert (not (nil? (urlencoded identity))) "urlencoded")
(assert (function? (urlencoded identity)) "urlencoded function")
(assert (deep=
          ((urlencoded identity)
            @{:headers
              {"Content-Type" "application/x-www-form-urlencoded"}
              :body "name=pepe%20calvera&fair=true\r\n"})
          @{:headers
            {"Content-Type" "application/x-www-form-urlencoded"}
            :body @{"name" "pepe calvera" "fair" true}})
        "urlencoded body")
(assert (deep=
          ((urlencoded identity)
            @{:headers
              {"Content-Type" "application/x-www-form-urlencoded"}
              :body "name=pepe+calvera&phone=%2B111\r\n"})
          @{:headers
            {"Content-Type" "application/x-www-form-urlencoded"}
            :body @{"name" "pepe calvera" "phone" "+111"}})
        "urlencoded body with +")

(assert (function? (multipart identity)) "multipart function")
(assert (deep=
          ((multipart identity)
            @{:headers
              {"Content-Type" "multipart/form-data; boundary=hi"}
              :body "--hi\r\nContent-Disposition: form-data; name=\"myTextField\"\r\n\r\ntest\r\n--hi\r\nContent-Disposition: form-data; name=\"myCheckBox\"\r\n\r\non\r\n--hi--\r\n"})
          @{:headers
            {"Content-Type" "multipart/form-data; boundary=hi"}
            :body @{"myTextField" "test" "myCheckBox" "on"}})
        "multipart parse body")
(assert (deep=
          ((multipart identity)
            @{:headers
              {"Content-Type" "multipart/form-data; boundary=---------------------------8721656041911415653955004498"}
              :body "-----------------------------8721656041911415653955004498\r\nContent-Disposition: form-data; name=\"myTextField\"\r\n\r\nTest\r\n-----------------------------8721656041911415653955004498\r\nContent-Disposition: form-data; name=\"myCheckBox\"\r\n\r\non\r\n-----------------------------8721656041911415653955004498\r\nContent-Disposition: form-data; name=\"myFile\"; filename=\"test.txt\"\r\nContent-Type: text/plain\r\n\r\nSimple file.\r\n-----------------------------8721656041911415653955004498--\r\n"})
          @{:headers
            {"Content-Type" "multipart/form-data; boundary=---------------------------8721656041911415653955004498"}
            :body @{"myCheckBox" "on" "myFile"
                    {:content "Simple file."
                     :filename "test.txt"
                     :content-type "text/plain"} "myTextField" "Test"}})
        "multipart parse body with file")

(assert (function? (cookies identity)) "cookies functions")
(assert
  (deep=
    ((cookies identity) @{:headers @{"Cookie" "some=value; other=other-value"}})
    @{:headers @{"Cookie" @{"some" "value" "other" "other-value"}}})
  "parse cookies")

(assert (not (nil? (html-success identity))) "html-success")
(assert (function? (html-success identity)) "html-success function")
(assert (deep= ((html-success (fn [req] "Success")) "")
               @"HTTP/1.1 200 OK\r\nContent-Length: 7\r\nContent-Type: text/html; charset=UTF-8\r\n\r\nSuccess"))

(assert (function? (stream (event :data "hoho"))))

(assert (deep= (style [[".chart rect" {:fill :black}]])
               @".chart rect {fill: black;}"))
(assert (do
          (make-wrap span)
          (= [:span {:class "big"} "small"] ((<span/> :big) "small"))))
(end-suite)

(os/exit)
