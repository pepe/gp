(use spork/misc)

(defn- image-file [self]
  (string (self :image) ".jimage"))

(defn- save-image [store]
  (spit (:image-file store)
        ((store :make-image) store)))

(defn- _get [store & path]
  (if-let [guide (and (one? (length path))
                      (function? (first path))
                      (first path))]
    (guide (store :root))
    (get-in store [:root ;path])))

(defn- _put [store what & path]
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

(defn- _geti [store uuid]
  (-?>> uuid ident-path (get-in store) first))

(defn- _getp [store uuid]
  (-?>> uuid ident-path (get-in store) last))

(defn- _put-ident [store what & path]
  (when (table? what)
    (if-let [uuid (what :uuid)]
      (put-in store (ident-path uuid) [what path])))
  (put-in store [:root ;path] what))

(def IdentityStore
  "Store with identity index"
  (make Store :getp _getp :geti _geti :put _put-ident))
