(use spork/test spork/misc ../gp/data)
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

(start-suite "Server shutdown")
# Close before the accepting task runs. On Windows this used to turn the
# deliberate close into a supervisor error because net/accept raised rather
# than returning nil.
(def shutdown-events (ev/chan 1))
(def [shutdown-acceptor shutdown-listener]
  (server/start shutdown-events "localhost" 8002))
(:close shutdown-listener)
(ev/sleep 0.01)
(assert (= :dead (fiber/status shutdown-acceptor))
        "closed server acceptor finishes")
(def replacement-listener (net/listen "localhost" 8002))
(:close replacement-listener)
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

(start-suite "SSE head")
# A stream is the only kind of response that can carry a Set-Cookie into a
# posture change, so the head has to be extensible and has to stay well
# formed when nothing is added to it.
(defn- head-of [stream-fn]
  (def written @"")
  (stream-fn @{:write (fn [self s] (buffer/push written s) self)
               :flush (fn [self] self)})
  (first (string/split "\r\n\r\n" (string written))))

(assert (= (head-of (stream))
           (string/trimr
             "HTTP/1.1 200 OK\r\nX-Accel-Buffering: no\r\nContent-Type: text/event-stream; charset=UTF-8\r\ntransfer-encoding: chunked\r\ncache-control: no-cache\r\nconnection: keep-alive\r\n"
             "\r\n"))
        "a plain stream head is unchanged")

(assert (string/find "Set-Cookie: session=abc; Max-Age=0;"
                     (head-of (stream-with (cookie "session" "abc; Max-Age=0;"))))
        "a stream head carries a cookie")

(assert (string/find "Content-Type: text/event-stream"
                     (head-of (stream-with (cookie "session" "abc"))))
        "and still says what it is")

# A blank line ends the head. Two of them would end it early and push the
# cookie into the body, where it is just text.
(assert (not (string/find "\r\n\r\n\r\n"
                          (head-of (stream-with (cookie "session" "abc")))))
        "adding a header does not close the head twice")
(assert (string/has-suffix? "connection: keep-alive"
                            (head-of (stream)))
        "and a stream without headers ends its head where it always did")
(assert (string/has-suffix? "Connection: close"
                            (head-of (stream-with {"Connection" "close"})))
        "a closing stream does not also advertise keep-alive")
(end-suite)

(start-suite "SSE writer")
# Janet allows one write in flight per stream. A second fiber writing
# under the first is not resumed when the first is done -- it is not
# resumed at all -- so what a missing turn costs is a fiber parked for
# the life of the process. The bytes are the thing that looks fine.
(def written-back (ev/chan 2))
(def write-server
  (net/server
    "localhost" 8043
    (fn [conn]
      (def acc @"")
      (def part @"")
      (forever
        (buffer/clear part)
        (def [open? read] (protect (:read conn 65536 part)))
        (if (or (not open?) (nil? read)) (break))
        (buffer/push acc part))
      (ev/give written-back acc))))
(ev/sleep 0.1)
(def write-conn (net/connect "localhost" 8043))
(def handle (sse-writer write-conn))
(def finished (ev/chan 8))
(ev/spawn (:write handle "AAAA") (ev/give finished :a))
(ev/spawn (:write handle "BBBB") (ev/give finished :b))
(ev/spawn (:write handle "CCCC") (ev/give finished :c))
(ev/sleep 0.5)
(assert (= 3 (ev/count finished))
        "every fiber writing one stream at once is resumed")
(:close write-conn)
(ev/sleep 0.2)
(assert (= "AAAABBBBCCCC" (string (ev/take written-back)))
        "and what they wrote arrives whole and in order")
(:close write-server)
(end-suite)

(start-suite "SSE keepalive")
# The half worth proving rather than assuming: that a stream whose reader
# has gone is actually reaped. Before the keepalive it never was -- the
# fiber stayed parked and subscribed, and the connection stayed open,
# because a server learns a connection is dead only when it next writes
# and a quiet stream never writes.
(setdyn *sse-keepalive* 0.2)
(def never (ev/chan))
(ev/spawn
  (def sc (ev/chan))
  (server/start sc "localhost" 8042)
  (supervisor sc (on-connection (fn [_] (stream (ev/take never))))))
(ev/sleep 0.2)

(def tasks-before (length (ev/all-tasks)))
(def reader (net/connect "localhost" 8042))
(:write reader "GET /stream HTTP/1.1\r\nHost: localhost\r\n\r\n")
(def heard @"")
(:read reader 4096 heard 1)
(assert (string/find "text/event-stream" (string heard)) "the stream opened")

(buffer/clear heard)
(:read reader 4096 heard 1)
(assert (string/find ": keepalive" (string heard))
        "a stream with nothing to say still says something")
(assert (string/has-prefix? "d\r\n" (string heard))
        "and says it as a chunk like any other")

(assert (> (length (ev/all-tasks)) tasks-before)
        "a stream in flight is a task of its own")
(:close reader)
(ev/sleep 1.5)
(assert (= tasks-before (length (ev/all-tasks)))
        "and a stream whose reader has gone stops being one")

# The guard is a fiber inside the connection's task, so without a supervisor
# of its own it reports to the connection's -- once when it finishes, and
# again, tagged `:error`, when the ending stream cancels a fiber that has
# already stopped. Both carry `protect`'s tuple as their value, and both
# arrive looking like a connection that failed, because a spawned fiber
# shares its parent's dynamic table and so carries `:conn` too.
(def isolated (ev/chan 16))
(def taken (ev/chan 1))
(def listener (net/listen "localhost" 8046))
(ev/spawn (ev/give taken (net/accept listener)))
(def client (net/connect "localhost" 8046))
(def served (ev/take taken))
(def parks (stream (ev/take (ev/chan))))
(ev/go (fiber/new (fn [&] (setdyn :conn served) (parks served)) :tp) nil isolated)
(ev/sleep 0.5)
(:close client)
(ev/sleep 1.5)
(var strangers 0)
(while (pos? (ev/count isolated))
  (def [_ fib] (ev/take isolated))
  (if (indexed? (fiber/last-value fib)) (++ strangers)))
(assert (zero? strangers)
        "the keepalive guard reports to nobody but itself")
(:close listener)

(setdyn *sse-keepalive* nil)
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
(let [resp (found "/")]
  (assert ((?find "302 Found") resp) "Found status")
  (assert ((?find "Location: /") resp) "Found location")
  (assert ((?find "Content-Length: 0") resp) "Found location"))
(let [resp (see-other "/")]
  (assert ((?find "303 See Other") resp) "See other status")
  (assert ((?find "Location: /") resp) "See other location")
  (assert ((?find "Content-Length: 0") resp) "See other location"))
(let [resp (switching-protocols "s3pPLMBiTxaQ9kYGzzhZRbK+xOodeep=")]
  (assert ((?find "101 Switching Protocols") resp) "Switching protocols status")
  (assert ((?find "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOodeep=") resp) "Switching protocols accept")
  (assert ((?find "Connection: Upgrade") resp) "Switching protocols upgrade")
  (assert ((?find "Upgrade: websocket") resp) "Switching protocols upgrade")
  (assert ((?find "Content-Length: 0") resp) "Switching protocols location"))
(assert (deep= (not-modified)
               @"HTTP/1.1 304 Not Modified\r\nContent-Length: 0\r\n\r\n"))
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
(assert ((?find "Set-Cookie: some=value") (http {:status 200 :body "Success" :headers (cookie "some" "value")}))
        "http response with cookie")
(assert ((?find "Set-Cookie: other=value")
          (http {:status 200
                 :body "Success"
                 :headers (cookie "other" "value"
                                  (cookie "some" "value"))}))
        "http response with more cookies")
(assert ((?find "Set-Cookie: other=10")
          (http {:status 200
                 :body "Success"
                 :headers (cookie "other" 10
                                  @{"Set-Cookie" @{"some" "value"}})}))
        "http response with more cookies")

(assert (= (tag "h4" "Header 4" {:class "important" :tabindex 3})
           `<h4 tabindex="3" class="important">Header 4</h4>`)
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
  (= ((drive {"/home" {"/sweet" {"/home" :home}} :not-found :not-found})
  (parse-request (string/replace "?a=b" "home/sweet/home" request))) :home)
  "nested routes to home")

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
(let [resp ((typed @{".html" :html
                     ".csv" :csv})
             @{:headers {"Accept" "text/xml"}})]
  (assert ((?find "415 Unsupported Media") resp) "Unsupported status") 
  (assert ((?find "'text/html'") resp) "Unsupported supported types")
  (assert ((?find "'text/csv'") resp) "Unsupported supported types")
  (assert ((?find "Media '.xml' is not supported, please use one of") resp) "Unsupported body"))

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
        (+ "inf" (some (+ :d))) "rq/s\n" -1)
    ((capture-stderr ((journal success)
                       @{:uri "/" :method "GET" :query-string "a=b"})) 1))
  "prints the log peg")
(assert
  (with-dyns [:out @""]
    (deep= @"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Type: text/plain\r\n\r\nOK"
           (suppress-stderr ((journal (fn [_] (success)))
                              @{:uri "/" :method "GET" :query-string "a=b"}))))
  "returns the response")
# A stream is a function the server hands the connection, not rendered
# bytes, so there is no head here to read -- and saying nothing about it
# hid every SSE request there is.
(assert
  (string/has-prefix?
    "stream GET /content?datastar=%7B%7D in "
    ((capture-stderr ((journal (fn [_] (stream)))
                       @{:uri "/content" :method "GET"
                         :query-string "datastar=%7B%7D"})) 1))
  "prints the log for a stream")
(assert
  (function?
    (suppress-stderr ((journal (fn [_] (stream)))
                       @{:uri "/content" :method "GET" :query-string ""})))
  "and still hands the stream back to be written")

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
# A browser offers every cookie whose domain and path match, and two of one
# name differing in either are two cookies. Keeping only the last let one
# host's session be answered as absent because another host's was newer.
(assert
  (deep=
    ((cookies identity)
      @{:headers @{"Cookie" "session=first; other=value; session=second"}})
    @{:headers @{"Cookie" @{"session" @["first" "second"]
                            "other" "value"}}})
  "keeps every value of a repeated cookie, in the order it was sent")
(assert
  (deep=
    ((cookies identity) @{:headers @{"Cookie" "a=1; a=2; a=3"}})
    @{:headers @{"Cookie" @{"a" @["1" "2" "3"]}}})
  "however many there are")

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
