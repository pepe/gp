# Socket claims and streams stay outside serializable application state.
(import ../ownership)

(def- held @{})

(defn path?
  "Whether `path` names a portable, absolute filesystem Unix socket."
  [path]
  (and (string? path) (> (length path) 1) (<= (length path) 103)
       (= "/" (slice path 0 1)) (not (string/find "\0" path))
       (not (string/find "//" path))
       (not (string/find "/./" (string path "/")))
       (not (string/find "/../" (string path "/")))
       (not= "/" (slice path (- (length path) 1)))))

(defn connect
  ```
  Connects as `net/connect` does, and collects at once what a refused
  connection leaves behind.

  Janet wraps the socket in a stream before connecting, and a connection
  refused there and then -- as one to a Unix socket always is -- closes
  the bare descriptor and raises, leaving the stream believing it still
  holds that number. The collector closes the number again whenever it
  reaches the stream, and by then it is usually someone else's. A
  guardian taking its door back after a handover listened on the very
  number its own probe had been refused on, and some while later the
  collector closed the listener under it: the path stayed, every
  connection to it was refused, and nothing was logged.

  Nothing is opened between the refusal and the collection here, so the
  number the stream lets go of is still nobody's.
  ```
  [host port]
  (def [ok result] (protect (net/connect host port)))
  (unless ok
    (gccollect)
    (error result))
  result)

(defn- remove-stale!
  [path]
  (when-let [stat (os/lstat path)]
    (assert (= :socket (stat :mode)) (string "Refusing non-socket path " path))
    (def [live connection] (protect (ev/with-deadline 0.5 (connect :unix path))))
    (when live (:close connection))
    (assert (not live) (string "Unix socket is already listening: " path))
    # A timeout or denied connection is not evidence of a stale socket.
    (assert (and (string? connection) (string/find "Connection refused" connection))
            (string "Cannot prove Unix socket is stale: " path ": " connection))
    (os/rm path)))

(defn- remove-own!
  ```
  Removes `path` if it is still the socket bound there as `inode`.

  A listener just closed under its own claim is known to be stale, and
  asking it is what left the descriptor that closed the next listener.
  ```
  [path inode]
  (def stat (os/lstat path))
  (when (and stat inode (= :socket (stat :mode)) (= inode (stat :inode)))
    (os/rm path)))

(defn listen
  ```
  Claims and binds a Unix socket, recovering only a refused stale socket.

  The parent must already exist and be writable only by its owner. A stable
  sibling `.lock` is held until close or process death; never unlink it.
  Run under umask 077. Permissions default to 0600; HTTP may use 0660 in a
  group-readable directory whose group is shared with the reverse proxy.
  ```
  [path &opt permissions]
  (assert (not= :windows (os/which)) "Unix sockets require a POSIX runtime")
  (assert (path? path) "A Unix socket needs an absolute path of at most 103 bytes")
  (default permissions 8r600)
  (assert (or (= permissions 8r600) (= permissions 8r660)) "Socket permissions must be 0600 or 0660")
  (def claim (ownership/acquire (string path ".lock")))
  (var listener nil)
  (var inode nil)
  (def [ok result]
    (protect
      (remove-stale! path)
      (set listener (net/listen :unix path :stream true))
      (set inode (os/lstat path :inode))
      (os/chmod path permissions)
      (put held listener {:path path :claim claim :inode inode})
      listener))
  (unless ok
    (when listener
      (protect (:close listener))
      (protect (remove-own! path inode)))
    (ownership/release claim)
    (error result))
  result)

(defn close
  ```
  Closes a claimed listener, removes its stale pathname, and releases its claim.
  Repeated close cannot unlink a later owner's socket. Accepted connections
  survive, so a handover can still finish its HTTP response after this call.
  ```
  [listener]
  (if-let [{:path path :claim claim :inode inode} (held listener)]
    (do
      (put held listener nil)
      (defer (ownership/release claim)
        (:close listener)
        (remove-own! path inode)))
    (protect (:close listener)))
  nil)

(defn close-all
  "Releases this process's Unix listeners before graceful application exit."
  []
  (each listener (keys held) (close listener)))
