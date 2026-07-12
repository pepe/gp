# Store persists its `:root` table as a Janet core "image" (the same
# marshalling format used by `janet -c`), via the core `make-image`/
# `load-image` functions referenced directly in the `Store` prototype
# below. That lets it round-trip arbitrary Janet values, including
# functions, without a separate serialization format.
#
# Everything below is a private implementation of `Store`'s methods —
# call them through the table (`:load`, `:save`, `:transact`, `:init`,
# `:flush`), not as bare functions.

(use spork/misc ./navigation)

(defn- image-file [self]
  (string (self :image) ".jimage"))

(defn- save-image
  "Saves the `store` to the image file."
  [store]
  (spit (:image-file store)
        ((store :make-image) store)))

(defn- load
  "Load an item on `path` from `store`."
  [{:root root} & path]
  (case (length path)
    0 root
    1 (in root (first path))
    (get-in root path)))

(defn- transact
  "Transact traverse navigation `nav` on the `store`"
  [store & nav]
  (if (empty? nav)
    store
    ((traverse ;nav) (store :root))))

(defn- save
  ```
  Saves `what` on optional `path` to `store`, and index it.
  All but the last segment of `path` must already exist as containers
  in `store` — this does not auto-vivify intermediate structure.
  ```
  [store what & path]
  (if (empty? path)
    (put store :root what)
    (let [container
          (if (one? (length path))
            (store :root)
            (get-in store [:root ;(slice path 0 -2)]))]
      (put container (last path) what))))

(defn- flush
  "Flushes store to the image file."
  [store]
  (save-image store)
  store)

(defn- init
  "Initializes store"
  [self]
  (def imf (:image-file self))
  (merge-into
    self
    (if (os/stat imf)
      ((self :load-image) (slurp imf))
      @{:root @{}})
    {:image (self :image)})
  (flush self))

(def Store
  ```
  Basic data store, and the only public binding in this module — use it
  via its methods (`:init`, `:load`, `:save`, `:transact`, `:flush`),
  not via bare function calls. Call `:init` before use, and `:flush`
  (or `:save` followed by `:flush`) to persist. `:make-image`/
  `:load-image` are Janet's core image marshalling functions, not
  local definitions.
  ```
  @{:init init
    :flush flush
    :image "store"
    :load load
    :transact transact
    :save save
    :make-image make-image
    :load-image load-image
    :image-file image-file})
