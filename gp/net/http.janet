(use spork/http spork/misc)
(import spork/json)
(import spork/temple)
(import spork/path)

(import ./server)
(import ./uri)
(import ../route)
(import ../utils)
(temple/add-loader)

# Reading part
(def buff-size "Default buffer size" 16384)

(utils/setup-peg-grammar)

(def- content-length-grammar
  (peg/compile
    ~{:cl "Content-Length: "
      :main (* (thru :cl) (/ '(to :crlf) ,scan-number)
               (thru (repeat 2 :crlf))
               (/ '(to -1) ,(fn content-length [b] (if b (length b) 0))))}))

(defn ensure-length
  ```
  Ensures that request is read whole in the most cases.
  Uses multiple passes according to the type of the request.
  It clears the request if it cannot be read in 32 pasess of
  16384 bytes.
  ```
  [connection req]
  (var reading 32)
  (var last-index 0)
  (while (pos? reading)
    (cond
      (def cls (string/find "Content-Length:" req))
      (do
        (var len-diff (- ;(peg/match content-length-grammar req cls)))
        (if (pos? len-diff)
          (:chunk connection len-diff req))
        (set reading 0))
      (not (string/find "\r\n\r\n" req))
      (do
        (:read connection buff-size req)
        (if (string/find "\r\n\r\n" req last-index)
          (set reading 1)
          (do
            (set last-index (length req))
            (if (one? reading) (buffer/clear req))
            (-- reading))))
      (set reading 0))))

(defn on-connection
  ```
  It takes `handler` with the user function,
  that will handle connections.
  Returns function for handling incomming connection,
  suitable for a default supervisor handling argument.
  Returned function reads the request and ensure its length.
  If it cannot be read in `ensure-length` it will write
  Entity too large response to the connection and closes it.
  ```
  [handler]
  (assert (function? handler) "Handler is not valid")
  (fn on-connection [connection]
    (def req (buffer/new buff-size))
    (forever
      (buffer/clear req)
      (protect (:read connection buff-size req))
      (when (empty? req)
        (ev/give-supervisor :close connection)
        (break))
      (ensure-length connection req)
      (when (empty? req)
        (:write connection
                "HTTP/1.1 413 Request Entity Too Large\r\nContent-Length: 24\r\nContent-Type: text/plain\r\n\r\nRequest Entity Too Large")
        (ev/give-supervisor :close connection)
        (break))
      (def res (handler req))
      (if (bytes? res)
        (ev/write connection res)
        (res connection)))))

# Managing part
(def- windows-closing-errors
  ```
  The Windows error codes that mean the other end of a connection has
  gone. ERROR_NETNAME_DELETED and ERROR_CONNECTION_ABORTED are a reset
  and an abort as ReadFile and WriteFile report them, and those are the
  calls Janet reads and writes a socket with. WSAECONNABORTED and
  WSAECONNRESET are the same two through Winsock's own calls.
  ```
  [64 1236 10053 10054])

(defn- windows-messages
  ```
  The text Janet raises for each of the Windows error `codes`, or an
  empty array where there is no way to ask for it: no FFI, or a sandbox
  that withholds it.

  On Windows, Janet raises a failed socket call as the description
  `FormatMessageA` gives of its error code, in the language of the
  machine, and keeps nothing else. The code is gone by the time the
  error can be caught, and the text differs from machine to machine, so
  the only thing to compare an error against is that same description,
  asked for with the same flags and cut at the same line end as
  `janet_ev_lasterr` cuts it.
  ```
  [codes]
  (compif (and (= :windows (os/which)) (dyn 'ffi/native))
    (try
      (do
        (def format-message
          (ffi/lookup (ffi/native "kernel32.dll") "FormatMessageA"))
        (def signature
          (ffi/signature :default :u32 :u32 :ptr :u32 :u32 :ptr :u32 :ptr))
        (seq [code :in codes]
          (def buf (buffer/new-filled 256 0))
          # FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, in
          # MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), as Janet asks.
          (def len
            (ffi/call format-message signature
                      0x1200 nil code 0x400 buf (length buf) nil))
          (if (zero? len)
            (string code)
            (first (peg/match '(<- (to (+ (set "\0\r\n") -1))) buf)))))
      # A sandbox without `:ffi` refuses `ffi/native`. Raising here would
      # fail every `closed-err?` the process asks, and so every failure a
      # supervisor tries to tell from a reader that left.
      ([_] @[]))
    @[]))

(var- closed-messages
  ```
  The localised messages `closed-err?` takes for a closed connection.

  Asked for on first use rather than at load, so that an image built on
  one machine does not carry that machine's language to another.
  ```
  nil)

(defn closed-err?
  ```
  Checks if the error is one of the closing ones.

  On Windows a reset connection is refused in the machine's own
  language, so what is compared there is the text Janet would raise for
  each of `windows-closing-errors`, asked of Windows itself. That is
  asked through the FFI on the first call, so a process that sandboxes
  itself without `:ffi` calls this once before, or it knows only the
  messages named here.
  ```
  [err]
  (unless closed-messages
    (set closed-messages (windows-messages windows-closing-errors)))
  (or (= err :client-disconnected)
      (= err "Connection reset by peer")
      (= err "stream is closed")
      (= err "Broken pipe")
      # What Janet raises itself when a write in flight on Windows ends
      # with the peer gone, or when a POSIX write takes nothing.
      (= err "disconnect")
      (has-value? closed-messages err)))

(defn response-started?
  ```
  Whether the connection `fiber` failed on had already been sent the
  head of its response.

  A failure is answered with a response of its own, and that is only an
  answer while nothing has gone out yet. Once a chunked body has begun, a
  second head lands inside it, where a reader takes `HTTP/1.1 500` for a
  chunk length that is not a number and drops the connection -- nginx
  says "upstream sent invalid chunked response", and the browser is left
  with a 200 whose body ends before it began.
  ```
  [fiber]
  (get (fiber/getenv fiber) :http/response-started))

(defn- end-failed-body
  ```
  Ends a chunked body whose writer failed after its head went out, then
  raises the failure again for the supervisor.

  The body is ended rather than cut. What was sent is valid as far as it
  goes, and a reader that sees a clean end does not mistake the failure
  for a broken connection -- a fetch that errors may be retried, and a
  retried POST is a command given twice. The failure itself is the
  supervisor's to report; `response-started?` tells it there is nobody
  left to answer. The connection is closed either way: the fiber that
  would read its next request is the one failing.
  ```
  [conn err fib]
  (setdyn :http/response-started true)
  (unless (closed-err? err)
    (protect (:write conn "0\r\n\r\n") (:flush conn)))
  (protect (:close conn))
  (propagate err fib))

(defmacro supervisor
  ```
  It takes `chan` as the supervising channel of the server
  and `handling` as the handling function.
  This supervisor is used by default if you do not
  provide your own to `server`.
  ```
  [chan handling & rules]
  (def additional-rules
    ~[,;rules
      [:error fiber]
      (let [err (fiber/last-value fiber)]
        (unless (,closed-err? err)
          (debug/stacktrace fiber err)
          (def conn ((fiber/getenv fiber) :conn))
          (unless (,response-started? fiber)
            (protect
              (:write conn
                      "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\nContent-Type: text/plain\r\n\r\nInternal Server Error")))
          # What a failed fiber left under :conn is whatever it last had
          # there, which need not be a connection and need not still be
          # open. Answering is worth trying; closing is not worth dying on.
          (protect (:close conn))))])
  ~(as-macro ,server/supervisor ,chan ,handling ,;additional-rules))

(defmacro server
  ```
  Convenience for spawning http server with default `supervisor`.
  
  It has one parameter `handler` with the function, that handles the requests.
  
    It also takes three optional parameters:
  - `host` hostname to bind to.
  - `port` port to bind to.
  - `rules` variadic rules' pairs for the supervisor pattern matching.
  ```
  [handler &opt host port & rules]
  ~(as-macro ,server/spawn ,supervisor (,on-connection ,handler)
             ,host ,port ,;rules))

# Utils
(defn coerce-fn
  "Coerce any non fn to the fn returning it."
  [action]
  (if (function? action) action (fn coerced-action [r] action)))

(defn- caprl [m u q v]
  {:method m
   :uri u
   :query-string q
   :http-version v})

(defn- caph [n c] {n c})

(defn- colhs [& hs] {:headers (merge ;hs)})

(defn- capb [b] {:body b})

(defn- colr [& xs] (merge ;xs))

(def- request-grammar
  (peg/compile
    ~{:sp " "
      :http "HTTP/"
      :cap-to-sp (* '(to :sp) :sp)
      :request (/ (* :cap-to-sp '(to (+ "?" :sp))
                     (any "?") :cap-to-sp :http :cap-to-crlf) ,caprl)
      :header (/ (* (not :crlf) '(to ":") ": " :cap-to-crlf) ,caph)
      :headers (/ (* (some :header) :crlf) ,colhs)
      :body (/ '(any (to -1)) ,capb)
      :main (/ (* :request :headers :body) ,colr)}))

(defn parse-request
  "Parses the http request."
  [reqs]
  ((peg/match request-grammar reqs) 0))

(defn url-path
  "Matches the path from the first line of `req`."
  [req]
  ((peg/match '(* "GET " '(to " HTTP")) req) 0))

(def mime-types
  "Mime types lookup table from file extension"
  {"*" "*/*"
   ".html" "text/html"
   ".htm" "text/html"
   ".txt" "text/plain"
   ".css" "text/css"
   ".js" "application/javascript"
   ".json" "application/json"
   ".xml" "text/xml"
   ".svg" "image/svg+xml"
   ".jpg" "image/jpeg"
   ".jpeg" "image/jpeg"
   ".gif" "image/gif"
   ".png" "image/png"
   ".wasm" "application/wasm"
   ".ico" "image/x-icon"
   ".csv" "text/csv"
   ".sse" "text/event-stream"})

(def mimes-charsets "Mime charsets that defaults to UTF-8"
  [".html" ".htm" ".json" ".xml" ".svg" ".sse"])

(defn render-headers
  ```
  Renders `headers` as http header lines, terminated but not closed: the
  blank line ending the head is the caller's to write, because a caller
  usually has its own headers to add first.

  A dictionary value is written once per pair as `k=v`, which is the shape
  `cookie` returns; an indexed one is joined with commas.
  ```
  [headers]
  (def hs @"")
  (loop [[n c] :pairs headers]
    (if (dictionary? c)
      (loop [[k v] :pairs c]
        (xprinf hs "%s: %s\r\n"
                (string n)
                (string/format "%s=%s" k v)))
      (xprinf hs "%s: %s\r\n"
              (string n)
              (if (indexed? c)
                (string/join c ",")
                (string c)))))
  hs)

(defn http
  ```
  Turns a response dictionary into an http response string.
  It only uses contents under `:status`, `:body` and `headers`
  keys in the dictionary. They defaults to 200, "" and {}
  respectively.
  ```
  [{:status status :body body :headers headers}]
  (default status 200)
  (default body "")
  (default headers {})
  (def fh @"")
  (def dflth
    (if (< 300 status 399)
      {"Content-Length" 0}
      {"Content-Length" (string (length body))
       "Content-Type" (mime-types ".txt")}))
  (xprinf fh "HTTP/1.1 %d %s\r\n"
          status (get status-messages status "Unknown Status Code"))
  (xprin fh (render-headers (merge dflth headers)))
  (xprin fh "\r\n")
  (if (and body (not (empty? body)))
    (xprin fh (string body)))
  fh)

(defn chunked-http
  ```
  Turns a response dictionary into an http response string.
  It only uses contents under `:status`, `:body` and `headers`
  keys in the dictionary. `status` defaults to 200 and 
  `headers` defaults to {}. Body must be a fiber that yields
	chunks. Transfer-Encoding is set to chunked.
  ```
  [{:status status :body body :headers headers}]
  (default status 200)
  (default headers {})
  (assert body "Body fiber must be present")
  (def dflth
    (if (< 300 status 399)
      (error "Staus code cannot be 3XX")
      {"Content-Type" (mime-types ".txt")
       "Transfer-Encoding" "chunked"}))
  (fn chunked-http [conn]
    (defn conn-write [f & values]
      (ev/write conn (string/format f ;values)))
    (conn-write
      "HTTP/1.1 %d %s\r\n"
      status (get status-messages status "Unknown Status Code"))
    (conn-write "%s" (render-headers (merge dflth headers)))
    (conn-write "\r\n")
    (try
      (each chunk body
        (conn-write "%x\r\n%s\r\n" (length chunk) chunk))
      ([err fib] (end-failed-body conn err fib)))
    (conn-write "0\r\n\r\n")))

(defn write-chunk
  "Writes one chunk `s` to the `conn`"
  [conn s]
  (:write conn (string/format "%x\r\n%s\r\n" (length s) s)))

(defmacro event
  "Send type of data to SSE."
  [typ data]
  ~(,write-chunk
     (dyn :sse-conn)
     (if (= :data ,typ)
       (string "data: " ,data "\n\n")
       (string "event: " ,typ "\n" "data: " ,data "\n\n"))))

(def- sse-head
  "The head every SSE response opens with, short of its closing blank line."
  "HTTP/1.1 200 OK\r\nX-Accel-Buffering: no\r\nContent-Type: text/event-stream; charset=UTF-8\r\ntransfer-encoding: chunked\r\ncache-control: no-cache\r\nconnection: keep-alive\r\n")

(def- sse-close-head
  "HTTP/1.1 200 OK\r\nX-Accel-Buffering: no\r\nContent-Type: text/event-stream; charset=UTF-8\r\ntransfer-encoding: chunked\r\ncache-control: no-cache\r\n")

(defdyn *sse-keepalive*
  ```
  Seconds of silence an SSE stream may pass before writing a keepalive,
  or nil for a stream that writes none. Defaults to
  `sse-keepalive-interval`.
  ```)

(def sse-keepalive-interval
  ```
  Seconds between keepalive writes on an SSE stream, when nothing says
  otherwise.

  Twenty rather than thirty, against the sixty a proxy commonly allows a
  silent response. A peer that goes away is not always refused on the
  first write afterwards -- a connection closed politely takes the first
  write and refuses the second -- so the time to notice is up to twice
  this, and twice thirty is the timeout itself.
  ```
  20)

(def- sse-keepalive-comment
  ```
  What a stream writes to say nothing. It goes out chunked like anything
  else -- the body of an SSE response is framed, and bytes put into it
  raw are read as a chunk header, which is to say as a length that is not
  a number, and the reader drops the connection it was sent to save.

  A line beginning with a colon is a comment: an event stream carries it
  and no reader acts on it. Confirmed against the Datastar bundle this
  application pins rather than assumed from the specification, because
  the two differ here -- Datastar dispatches on every blank line, where
  the specification dispatches only on a non-empty one. What saves it is
  the next thing it does, which is to return unless the event name begins
  with `datastar`, and a comment leaves that name empty.
  ```
  ": keepalive\n\n")

(defn sse-writer
  ```
  A handle standing in for `conn` for the length of one SSE stream, so
  that only one fiber is ever writing it.

  Janet allows one write in flight per stream. A second fiber writing
  while another's write is still in flight does not braid the bytes --
  they arrive whole and in order -- it is simply never resumed, and parks
  for as long as the process lives. So the cost of a second writer is not
  a corrupted stream but exactly the abandoned fiber a keepalive exists
  to prevent.

  `ev/lock` is no help: it excludes threads, and these fibers share one.
  A channel holding a single token does, and the token is returned in a
  `defer`, so a writer that fails or is cancelled hands it back on its
  way out.

  Everything writes a stream as `(:write (dyn :sse-conn) ...)` already,
  so standing this in place of the connection asks nothing of any caller.
  ```
  [conn]
  (def turn (ev/chan 1))
  (ev/give turn true)
  @{:conn conn
    :write (fn sse-write [self s]
             (def token (ev/take turn))
             (defer (ev/give turn token)
               (:write conn s))
             self)
    :flush (fn sse-flush [self] (:flush conn) self)
    :close (fn sse-close [self] (:close conn) self)})

(defn- sse-guard
  ```
  Writes a keepalive to `handle` every so often, and ends `task` once one
  is refused. Returns the watching fiber, or nil if nothing is watching.

  A periodic write closes two things at once. It is what keeps a proxy
  from cutting a stream that has been silent too long, and it is the only
  way this end ever discovers that the other has gone: a server learns a
  connection is dead when it next writes, and a stream parked waiting for
  something to say never writes at all.

  It cannot be left to the body to notice. A body parked in `ev/take` is
  not waiting on its connection, and a body that does write is no better
  off, because the writes it makes are wrapped in `protect` by whoever
  offers them -- so even a stream writing every second swallows the
  refusal and goes on. What is different about this write is not that it
  can fail but that its failing is answered.

  Both the closing and the ending are ours. The supervisor keeps its
  whole recovery inside `(unless (closed-err? err) ...)`, so a stream
  that dies of a peer that has gone is closed by nobody; and the error
  the task is ended with is one `closed-err?` already knows, so this
  ordinary end of a stream is not reported as a fault.
  ```
  [handle task]
  (def interval (dyn *sse-keepalive* sse-keepalive-interval))
  (when (and interval (pos? interval))
    (ev/go
      (fiber/new
        (fn sse-watch [&]
          # Being cancelled is how this ordinarily ends, and a cancellation
          # is an error raised wherever the fiber was waiting. Nothing here
          # catches it: the mask below traps it and the supervisor channel
          # below takes it, so it reaches neither the root nor stderr.
          (forever
            (ev/sleep interval)
            (unless (first (protect (write-chunk handle sse-keepalive-comment)))
              (protect (:close handle))
              (ev/cancel task "stream is closed")
              (break))))
        :tp)
      nil
      # A supervisor of its own, that nothing reads.
      #
      # A fiber spawned inside a task reports to that task's supervisor,
      # and this one would arrive at an HTTP supervisor looking like a
      # connection fiber that failed -- carrying `:conn` from the dynamic
      # table it shares with its parent, since a child inherits that table
      # by reference rather than by copy. Worse, being cancelled after it
      # has already finished, which is what the ordinary end of a stream
      # does to it, posts a *second* message tagged `:error`. A supervisor
      # that prints what it is given then reports a stream that ended
      # perfectly well as a fault, twice over.
      #
      # Two messages at most reach here -- the cancellation that ends the
      # watch, and a late second one when the watch got there first -- and
      # both are meant for nobody.
      (ev/chan 4))))

(defmacro stream-with
  ```
  Creates new SSE stream carrying extra response `headers`.

  The head is the only place a stream can set a cookie. Once events are
  flowing the response head is long gone, and event data cannot reach an
  HttpOnly cookie from the browser side at all -- so a posture change that
  must also change a cookie has to say so here, before the first event.

  `headers` is evaluated once, at the moment the response opens.

  What the body writes to goes through `sse-writer` rather than being the
  connection itself, and a `sse-guard` writes to it while the body has
  nothing to say. The guard is cancelled the moment the body is done --
  it must not outlive the stream, because the connection is kept and the
  next request on it is answered by a fiber that would find a stranger
  writing into its response.

  A body that fails has its stream ended and its connection closed, and
  the failure goes on to the supervisor marked as `response-started?`,
  so that nobody answers it with a second head inside this one.
  ```
  [headers & body]
  (with-syms [conn hs handle guard err fib]
    ~(fn stream [,conn]
       (def ,hs ,headers)
       (:write ,conn
               (if ,hs
                 (string (if (= "close" (get ,hs "Connection"))
                           ,sse-close-head ,sse-head)
                         (,render-headers ,hs) "\r\n")
                 (string ,sse-head "\r\n")))
       (def ,handle (,sse-writer ,conn))
       (setdyn :sse-conn ,handle)
       (def ,guard (,sse-guard ,handle (fiber/root)))
       (defer (if ,guard (,ev/cancel ,guard "stream is closed"))
         # Ended through the handle, so the guard -- still running until
         # the defer -- cannot be writing a keepalive at the same moment.
         (try (do ,;body)
           ([,err ,fib] (,end-failed-body ,handle ,err ,fib)))
         # A stream that ends politely may have nobody left to say it to.
         # The terminating chunk is the only thing after the body, so a
         # refusal here means the reader has gone -- which is the ordinary
         # end of a stream, not a fault worth raising at a supervisor. It
         # only became reachable when streams began ending on purpose
         # rather than living until their connection died.
         (protect
           (:write ,handle "0\r\n\r\n")
           (:flush ,handle))
         (when (and ,hs (= "close" (get ,hs "Connection")))
           (protect (:close ,conn)))))))

(defmacro stream
  "Creates new SSE stream"
  [& body]
  ~(as-macro ,stream-with nil ,;body))

(defn response
  ```
  Creates response struct from http `code`, `body`
  and optional `headers`.
  ```
  [code body &opt headers]
  (default headers @{})
  (http
    {:status code
     :headers headers
     :body body}))

(defn success
  ```
  Return success response with optional `body` and `headers`.
  ```
  [&opt body headers]
  (default body (status-messages 200))
  (response 200 body headers))

(defn no-content
  ```
  Return no content response with optional `body` and `headers`.
  Per RFC 7231, a 204 response must not carry a body, so `body`
  defaults to `""` rather than any status message text.
  ```
  [&opt body headers]
  (default body "")
  (response 204 body headers))

(defn created
  ```
  Return created response with optional `body` and `headers`.
  ```
  [&opt body headers]
  (default body (status-messages 201))
  (response 201 body headers))

(defn found
  "Returns found response with `location`."
  [location]
  (response 302 "" {"Location" location "Content-Length" 0}))

(defn see-other
  "Returns see other response with `location`."
  [location]
  (response 303 "" {"Location" location "Content-Length" 0}))

(defn not-modified
  "Returns not modified response."
  []
  (response 304 ""))

(defn bad-request
  "Returns bad request response with optional `body` and `headers`."
  [&opt body headers]
  (default body (status-messages 400))
  (response 400 body headers))

(defn not-authorized
  "Returns not autorized response with optional `body` and `headers`."
  [&opt body headers]
  (default body (status-messages 401))
  (response 401 body headers))

(defn not-found
  "Returns not found response with optional `body` and `headers`."
  [&opt body headers]
  (default body (status-messages 404))
  (response 404 body headers))

(defn not-supported
  ```
  Returns not supported media type response
  with optional `body` and `headers`.
  ```
  [&opt body headers]
  (default body (status-messages 415))
  (response 415 body headers))

(defn method-not-allowed
  "Returns not allowed method type response with optional `body` and `headers`."
  [&opt body headers]
  (default body (status-messages 405))
  (response 405 body headers))

(defn internal-server-error
  "Returns internal server error response with optional `body` and `headers`."
  [&opt body headers]
  (default body (status-messages 500))
  (response 500 body headers))

(defn not-implemented
  ```
  Returns not implemented method type response
  with optional `body` and `headers`.
  ```
  [&opt body headers]
  (default body (status-messages 501))
  (response 501 body headers))

(defn switching-protocols
  "Returns switching protocols response with `key`"
  [key]
  (response 101 "" {"Upgrade" "websocket"
                    "Connection" "Upgrade"
                    "Sec-WebSocket-Accept" key}))

(defn content-type
  ```
  Returns Content-Type header for given `mime-type`.
  Optional `charset` defaults to UTF-8 where applicable.
  ```
  [mime-type &opt charset]
  (var mt (mime-types mime-type))
  (when (find |(= mime-type $) mimes-charsets)
    (default charset "UTF-8")
    (set mt (string mt "; charset=" charset)))
  {"Content-Type" mt})

(defn cookie
  ```
  Returns header for setting cookie with `value` under `key`.
  When optional `existing-cookie` header provided, it updates
  it with the new value.
  ```
  [key value &opt existing-cookie]
  (def [sk sv] [(string key) (string value)])
  (if existing-cookie
    (update existing-cookie "Set-Cookie" put sk sv)
    @{"Set-Cookie" @{sk sv}}))

(defn ->json
  "Encodes `data-structure` into json."
  [data-structure]
  (json/encode data-structure))

(defmacro page
  `Macro that converts temple template into html string`
  [name & body]
  (import* (string (dyn :templates "/templates") "/" name))
  (def iname
    (if-let [si (string/find "/" name)]
      (slice name (inc si))
      name))
  (def b (if (next body) body [{}]))
  (with-syms [args buf]
    ~(do
       (def ,buf @"")
       (def ,args ,;b)
       (with-dyns [:out ,buf]
         (,(symbol iname "/render-dict") ,args))
       (freeze ,buf))))

(defn page*
  "Function that converts temple template into html string"
  [name args]
  (def rend
    (-> (dyn :templates "/templates")
        (string "/" name)
        require
        (get-in ['render-dict :value])))
  (def buf @"")
  (with-dyns [:out buf] (rend args))
  (freeze buf))

(defn tag
  ```
  Returns string with html tag `name` with enclosed `content`.
  Optional `attrs` must be table of attributes.
  ```
  [name content &opt attrs]
  (default attrs {})
  (assert (dictionary? attrs))
  (def attrss @"")
  (loop [[k v] :pairs attrs]
    (buffer/push-string attrss " " k `="` (string v) `"`))
  (string `<` name attrss `>` content `</` name `>`))

(defn etag
  ```
  Returns string with html empty tag `name`.
  Optional `attrs` must be table of attributes.
  ```
  [name &opt attrs]
  (tag name "" attrs))

(defn ptag
  ```
  Prints html tag `name` with enclosed `content`.
  Optional `attrs` must be table of attributes.
  ```
  [name content &opt attrs]
  (prin (tag name content attrs)))

(defn petag
  ```
  Prints html empty tag `name`.
  Optional `attrs` must be table of attributes.
  ```
  [name &opt attrs]
  (prin (etag name attrs)))

(defn parser
  "Parses the http request into request table"
  [next-middleware]
  (fn parser [req]
    (next-middleware (parse-request req))))

# Middleware
(defn journal
  ```
  Middleware that logs the request.

  Every request is written, whatever it is answered with. A response is
  either rendered bytes, whose head can be read here, or a function the
  server hands the connection -- a stream or a chunked body, which writes
  its own head and then lives as long as it likes. There is no head to
  read for those and no end to time, and passing over them silently left
  every SSE request out of the journal: in an application driven by
  Datastar that is nearly all of them, so a place could answer all day and
  show one line for the document it opened with.

  What is timed is reaching the answer, not delivering it. A stream is
  handed back before its body runs, so its `:elapsed` is the dispatch and
  nothing more -- which is the only thing that has happened yet.
  ```
  [next-middleware &opt printer]
  (default printer
    |(eprintf "%s %s %s in %s, %s"
              ($ :head) ($ :method) ($ :fulluri) ($ :elapsed) ($ :reqs)))
  (def headg ''(thru (* " " :d+)))
  (fn journal [req]
    (def {:uri uri
          :method method
          :query-string qs} req)
    (def start (os/clock))
    (def resp (next-middleware req))
    (def elapsed (- (os/clock) start))
    (def head (if (bytes? resp) (peg/match headg resp)))
    (printer
      @{:method method
        :elapsed (utils/precise-time elapsed)
        :reqs (string/format "%irq/s"
                             (if (zero? elapsed) elapsed
                               (math/floor (/ 1 elapsed))))
        :head (if head (head 0) "stream")
        :fulluri (if (and qs (not (empty? qs)))
                   (string uri "?" qs) uri)})
    resp))


(defn drive
  ```
  Creates a router middleware.

  The first argument should be the table of routes you want to define.
  Keys are the bytes sequence with path, value is the function to call
  or table. In case of table key is used as prefix for all keys in value table.
  The subtable is then flattened with prefixes.

  If you define route :not-found that will be matched if no defined one does.
  ```
  [routes]
  (defn flatten-routes [acc prefix node]
    (loop [[k v] :pairs node]
      (if (= k :not-found)
        acc
        (let [path (string prefix k)]
          (if (dictionary? v)
            (flatten-routes acc path v)
            (put acc path (coerce-fn v))))))
    acc)
  (def comproutes (flatten-routes @{} "" routes))
  (def ruter (route/router comproutes))
  (def not-found-action
    (coerce-fn (get routes :not-found (not-found))))
  (fn drive [req]
    (def [action params] (ruter (req :uri)))
    (if action
      (action (put req :params (map-vals uri/unescape params)))
      (not-found-action req))))

(defn query-params
  "Parses query string into janet struct under :query-params key.
   Keys are keywordized"
  [next-middleware]
  (fn query-params [req]
    (def query-string (req :query-string))
    (if (empty? query-string)
      (next-middleware req)
      (do
        (-?>> query-string
              uri/parse-query
              (map-vals uri/unescape)
              (put req :query-params))
        (if (nil? (req :query-params))
          (bad-request "Query params have invalid format")
          (next-middleware req))))))

(defn urlencoded
  ```
  Creates middleware function, that parses urlencoded body
  into janet table with parameters. A value saying `true` or `false`
  becomes that boolean.

  `uri/parse-query` unescapes every key and value itself, so a value is
  not unescaped again: a second pass read a literal `%`, sent as `%25`,
  as the start of another escape.
  ```
  [next-middleware]
  (defn decode [body]
    (->> body
         string/trim
         (string/replace-all "+" "%20")
         uri/parse-query
         (map-vals |(case $ "false" false "true" true $))))
  (fn urlencode [req]
    (if (= (gett req :headers "Content-Type")
           "application/x-www-form-urlencoded")
      (update req :body decode))
    (next-middleware req)))

(defn- capfn [n c ct d]
  {n {:filename c
      :content-type ct
      :content d}})

(def- boundary-peg
  (peg/compile '(* "multipart/form-data; boundary=" '(to -1))))

(def- req-peg
  (peg/compile
    ~{:crlf "\r\n"
      :be "--"
      :boundary (drop (* :be (argument 0) (backmatch)))
      :boundaryn (* :crlf :boundary (? :be) :crlf)
      :quote "\""
      :cd "Content-Disposition: form-data; name="
      :fn (* "; filename=" :quote '(to :quote) :quote :crlf
             "Content-Type: " '(to :crlf))
      :header (* :cd :quote '(to :quote) :quote)
      :content (* '(to :boundaryn) :boundaryn)
      :field (/ (* :header (repeat 2 :crlf) :content) ,caph)
      :file (/ (* :header :fn (repeat 2 :crlf) :content) ,capfn)
      :main (* :boundary :crlf (/ (some (+ :field :file)) ,colr))}))

(defn multipart
  ```
  Creates middleware function, that parses multipart encoded body
  into janet table with parameters.
  ```
  [next-middleware]
  (fn multipart [req]
    (if-let [[boundary]
             (peg/match boundary-peg
                        (get-in req [:headers "Content-Type"]))]
      (update
        req :body
        |(first (peg/match req-peg $ 0 boundary))))
    (next-middleware req)))

(defn- cookie-jar
  ```
  Folds parsed cookie pairs into a table, keeping every value a repeated
  name was sent with.

  Two cookies of one name are distinct whenever their domain or path
  differ, and a browser offers every one that matches the request, in a
  single header, in an order the server is told not to rely on and with
  nothing to tell them apart. Folding them into one value picks whichever
  arrived last and drops the rest without a word -- so a session issued
  here is answered as absent because a cookie of the same name, issued by
  another host entirely, happened to be newer.

  A name sent once keeps its value exactly as it did. Only a name actually
  repeated becomes an array, so a reader meets the plural case precisely
  when there is one, and never otherwise.
  ```
  [pairs]
  (def jar @{})
  (each [name value] (partition 2 pairs)
    (def seen (jar name))
    (cond
      (nil? seen) (put jar name value)
      (array? seen) (array/push seen value)
      (put jar name @[seen value])))
  jar)

(defn cookies
  ```
  Creates middleware function, that parses the cookies from the headers.

  A name the browser sent more than once arrives as an array of every
  value it sent; see `cookie-jar` for why that is not collapsed here.
  ```
  [next-middleware]
  (def grammar
    '{:end (+ -1 "; ")
      :sep "="
      :pair (* '(to :sep) :sep '(to :end) :end)
      :main (some :pair)})
  (fn cookies [req]
    (if-let [ck (get-in req [:headers "Cookie"])]
      (put-in req [:headers "Cookie"] (cookie-jar (peg/match grammar ck))))
    (next-middleware req)))

(defn json->body
  ```
  Creates middleware that parses json in body
  into Janet struct under :body key
  ```
  [next-middleware]
  (fn json->body [req]
    (let [b (req :body)]
      (if (empty? b)
        (next-middleware req)
        (->> b
             json/decode
             (put req :body)
             next-middleware)))))

(defn guard-methods
  "Middleware for quarding only some http methods"
  [next-middleware & methods]
  (fn guard-methods [req]
    (def method (req :method))
    (if (or (= method "OPTIONS") (some |(= method $) methods))
      (next-middleware req)
      (method-not-allowed
        (string/format
          "Method '%s' is not supported. Please use %s"
          method (string/join methods " or "))))))

(defn guard-mime
  "Guards mime content type"
  [next-middleware mime]
  (def all-mime (mime-types "*"))
  (def req-mime (mime-types mime))
  (fn guard-mime [req]
    (def accept (get-in req [:headers "Accept"] "*/*"))
    (if (or (string/find all-mime accept) (string/find req-mime accept))
      (next-middleware req)
      (not-supported
        (string/format
          "Media '%s' is not supported, please use '%s' or '%s'"
          accept req-mime all-mime)))))

(defn dispatch
  ```
  Dispatches based on HTTP methods. Configuration is in
  the table where keys must be HTTP methods in allcaps.
  ```
  [config]
  (fn dispatch [req]
    (def method (req :method))
    (if-let [action (config method)]
      ((coerce-fn action) req)
      (not-implemented
        (string/format
          "Method %s is not implemented, please use %s"
          method (string/join (keys config) " or "))))))

(defn static
  ```
  Serves static files in a given directory.

  `miss` answers whatever is not a file on disk, and defaults to a 404. It
  exists because this handler is installed at `:not-found`, which is also
  where an application that answers one document for every path keeps that
  document -- putting the one there takes the other out. A response is
  rendered bytes by the time it comes back, so the choice cannot be made
  by looking at what this returns; it has to be made here, where the path
  rule is.
  ```
  [directory &opt default-index miss]
  (default default-index "index.html")
  (default miss (fn miss [_] (not-found)))
  # Joining normalizes, so a `..` in the request is already resolved here:
  # a file is served only when it is still beneath the directory. A raw
  # `GET /../conf.jdn` reached the configuration beside `public` before.
  (def root (string/trimr (path/join directory) "/\\"))
  (defn inside? [file]
    (and (string/has-prefix? root file)
         (index-of (get file (length root)) [(chr "/") (chr "\\")])))
  (fn static [req]
    (def uri (req :uri))
    (def path
      (if (string/has-suffix? "/" uri)
        (path/join root uri default-index)
        (path/join root uri)))
    (if (and (inside? path) (= :file (os/stat path :mode)))
      (response 200 (slurp path) (content-type (path/ext path)))
      (miss req))))

(defn typed
  ```
  Similar to dispatch, but works on mime types. Configuration is the
  table, where keys are mime extensions and values are functions to run.
  ```
  [config]
  (fn typed [req]
    (def accept (get-in req [:headers "Accept"] "*"))
    (def mime ((invert mime-types) accept))
    (if-let [action (config mime)]
      ((coerce-fn action) req)
      (not-supported
        (string/format
          "Media '%s' is not supported, please use one of %s."
          mime (string/join
                 (map (fn format-mime [m]
                        (string "'" (mime-types m) "'"))
                      (keys config)) ", "))))))

(defn html-success
  ```
  Create middleware which takes response and returns it with
  html-mime and success status
  ```
  [next-middleware]
  (fn html-success [req]
    (success (next-middleware req) (content-type ".html"))))

(defn style
  "Renders css style tag for `ds`"
  [ds]
  (do
    (def res @"")
    (loop [[e d] :in ds]
      (buffer/push res e " " "{")
      (loop [[n v] :pairs d]
        (buffer/push res n ": " v ";"))
      (buffer/push res "}"))
    res))

(defn html-success-resp
  "Wraps `resp` with success status and html mime"
  [resp &opt headers]
  (default headers @{})
  (merge-into headers (content-type ".html"))
  (success resp headers))

(defn html-get
  ```
  Guards the get http method, check the session and wraps `next-middleware`
  with the `html-success`.
  ```
  [next-middleware]
  (-> next-middleware
      (guard-methods "GET")
      html-success))

(defn keywordize-body
  "Make keys in body keywords"
  [next-middleware]
  (fn [req]
    (next-middleware
      (update req :body |(map-keys keyword $)))))

(defn urlenc-post
  ```
  Wraps the `next-middleware` in urlencode, guards the post method,
  flushes, rerenders and checks the session.
  ```
  [next-middleware]
  (-> next-middleware
      keywordize-body
      urlencoded
      (guard-methods "POST")))

(defn urlenc-put
  ```
  Wraps the `next-middleware` in urlencode, guards the put method,
  flushes, rerenders and checks the session.
  ```
  [next-middleware]
  (-> next-middleware
      keywordize-body
      urlencoded
      (guard-methods "PUT")))

(defn- process-attrs
  [attrs]
  (cond
    (empty? attrs) {}
    (all bytes? attrs) {:class (string/join attrs " ")}
    (dictionary? (attrs 0)) (freeze (attrs 0))))

(defmacro make-wrap
  "Creates function `<el/>` for wrapping"
  [el]
  (def name (symbol "<" el "/>"))
  (with-syms [attrs items]
    ~(defn ,name
       ,(string "Wraps item in " el)
       [& ,attrs]
       (fn ,name [& ,items]
         [,(keyword el) (,process-attrs ,attrs) ;,items]))))
