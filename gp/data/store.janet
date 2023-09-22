(use spork/misc)

(defn- image-file [self]
  (string (self :image) ".jimage"))

(defn save-image
  "Saves the `store` to the image file."
  [store]
  (spit (:image-file store)
        ((store :make-image) store)))

(defn- _get
  "Gets an item on `path` from `store`."
  [store & path]
  (if-let [guide (and (one? (length path))
                      (function? (first path))
                      (first path))]
    (guide (store :root))
    (get-in store [:root ;path])))

(defn- _put
  "Puts `what` on `path` to `store`, and index it."
  [store what & path]
  (put-in store [:root ;path] what))

(defn flush
  "Flushes store to the image file"
  [store]
  (save-image store)
  store)

(defn init
  "Initializes store"
  [self]
  (def imf (:image-file self))
  (merge-into
    self
    (if (os/stat imf)
      ((self :load-image) (slurp imf))
      @{:root @{} :index @{}})
    {:image (self :image)})
  (flush self))

(def Store
  "Basic data store"
  @{:init init
    :flush flush
    :image "store"
    :get _get
    :put _put
    :make-image make-image
    :load-image load-image
    :image-file image-file})

(defn- ident-path [uuid] [:index uuid])

(defn geti
  "Gets an item identified with `uuid` from `store`'s index."
  [store uuid]
  (-?>> uuid ident-path (get-in store) first))

(defn getp
  "Gets a path of item identified with `uuid` from `store`'s index."
  [store uuid]
  (-?>> uuid ident-path (get-in store) last))

(defn put-ident
  "Puts `what` on `path` to `store`, and index it."
  [store what & path]
  (when (table? what)
    (if-let [uuid (what :uuid)]
      (put-in store (ident-path uuid) [what path])))
  (put-in store [:root ;path] what))

(def IdentityStore
  "Store with identity index"
  (make Store :getp getp :geti geti :put put-ident))
