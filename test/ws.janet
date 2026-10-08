(use spork/test spork/misc gp/data)
(import gp/net/server)
(use gp/net/ws)
(start-suite "Documentation")
(assert-docs "gp/net/ws")
(end-suite)
(start-suite "Response")

(assert (= (string (response 0xA "Pong"))
           "\x8A\x04Pong")
        "response")

(assert (= (string (text "Hey")) "\x81\x03Hey")
        "text")

(assert (= (string (binary "Hey")) "\x82\x03Hey")
        "binary")

(end-suite)

(start-suite "supervisor on-connection")
(def c (ev/chan))
(def h @{:connect (fn [s c] (net/write (dyn :conn) (text "Connected")))
         :read (fn [s c m] (net/write (dyn :conn) (text (string "Received: " m))))
         :closed (fn [s])})
(ev/spawn
  (server/start c)
  (supervisor c (on-connection h)))

(ev/sleep 0.001)
(def w (net/connect "localhost" 8888))
(net/write w "Sec-WebSocket-Key: ABCDEF")
(ev/sleep 0.001)
(let [resp (net/read w 256)]
  (assert ((?find "101 Switching Protocols") resp) "Switching protocols status")
  (assert ((?find "Sec-WebSocket-Accept: Kfh9QIsMVZcl6xEPYxPHzW8SZ8w=") resp) "Handshake accept")
  (assert ((?find "Connection: Upgrade") resp) "Handshake upgrade")
  (assert ((?find "Upgrade: websocket") resp) "Handshake upgrade")
  (assert ((?find "Content-Length: 0") resp) "Handshake location"))
(end-suite)

(start-suite "server")
(server h "localhost" 8887)
(ev/sleep 0.001)
(def w (net/connect "localhost" 8887))
(net/write w "Sec-WebSocket-Key: HOHO")
(ev/sleep 0.001)
(let [resp (net/read w 256)]
  (assert ((?find "101 Switching Protocols") resp) "Switching protocols status")
  (assert ((?find "Sec-WebSocket-Accept: Kfh9QIsMVZcl6xEPYxPHzW8SZ8w=") resp) "Handshake accept")
  (assert ((?find "Connection: Upgrade") resp) "Handshake upgrade")
  (assert ((?find "Upgrade: websocket") resp) "Handshake upgrade")
  (assert ((?find "Content-Length: 0") resp) "Handshake location"))
(net/write w (string/from-bytes 9 129 256 256 256 256 38))
(assert (deep= (net/read w 256) @"\x8A\x01&") "ping")
(net/write w (string/from-bytes 129 129 256 256 256 256 38))
(assert (deep= (net/read w 256) @"\x81\fReceived: &&"))
(net/write w (string/from-bytes 8 129 256 256 256 256 38))
(:write h (text "Emitted"))
(assert (deep= (net/read w 256) @"\x81\x07Emitted") "emitted")
(assert (deep= (net/read w 256) @"\x88\x01&") "close")
(end-suite)

(start-suite "Handshake in any case")
# The key is read from the request's bytes, so its name has to be found in
# whatever case the client wrote it. Both handshakes carry a real key, so
# their accept is the key's, not the one a missing key gets.
(def lower-chan (ev/chan))
(ev/spawn
  (server/start lower-chan "localhost" 8886)
  (supervisor lower-chan (on-connection h)))
(ev/sleep 0.001)
(defn- accept-for [header]
  (def conn (net/connect "localhost" 8886))
  (net/write conn (string header ": dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"))
  (ev/sleep 0.001)
  (def resp (net/read conn 256))
  (:close conn)
  (first (peg/match '(* (thru "Sec-WebSocket-Accept: ") '(to "\r\n")) resp)))
(def proper (accept-for "Sec-WebSocket-Key"))
(assert (= "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" proper) "the key is read")
(assert (= proper (accept-for "sec-websocket-key")) "the key is read in lower case")
(end-suite)
(os/exit 0)
