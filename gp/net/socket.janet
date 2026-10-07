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

(defn- remove-stale!
  [path]
  (when-let [stat (os/lstat path)]
    (assert (= :socket (stat :mode)) (string "Refusing non-socket path " path))
    (def [live connection] (protect (ev/with-deadline 0.5 (net/connect :unix path))))
    (when live (:close connection))
    (assert (not live) (string "Unix socket is already listening: " path))
    # A timeout or denied connection is not evidence of a stale socket.
    (assert (and (string? connection) (string/find "Connection refused" connection))
            (string "Cannot prove Unix socket is stale: " path ": " connection))
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
  (def [ok result]
    (protect
      (remove-stale! path)
      (set listener (net/listen :unix path :stream true))
      (os/chmod path permissions)
      (put held listener {:path path :claim claim})
      listener))
  (unless ok
    (when listener
      (protect (:close listener))
      (protect (remove-stale! path)))
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
  (if-let [{:path path :claim claim} (held listener)]
    (do
      (put held listener nil)
      (defer (ownership/release claim)
        (:close listener)
        (remove-stale! path)))
    (protect (:close listener)))
  nil)

(defn close-all
  "Releases this process's Unix listeners before graceful application exit."
  []
  (each listener (keys held) (close listener)))
