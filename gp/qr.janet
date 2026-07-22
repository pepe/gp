(import ./qr-native :as _qr)

(defn encode
  ```
  Encode a UTF-8 string as a QR code. Accepts an optional `:ecc` keyword with
  `:low`, `:medium`, `:quartile`, or `:high`; the default is `:medium`.
  ```
  [payload & options]
  (def ecc
    (case (length options)
      0 :medium
      2 (if (= :ecc (options 0))
          (options 1)
          (errorf "unknown QR option %v" (options 0)))
      (error "qr/encode expects only the optional pair :ecc level")))
  (_qr/encode payload ecc))

(def size
  "Return the width and height of the QR code's logical module matrix."
  _qr/size)

(def module
  "Return whether the logical module at integer coordinates `x`, `y` is dark."
  _qr/module)

(defn svg
  ```
  Return an htmlgen SVG structure for `code`. The SVG has a four-module quiet
  zone, a white background, and one black path containing all dark modules.
  ```
  [code]
  (def quiet-zone 4)
  (def matrix-size (size code))
  (def image-size (+ matrix-size (* quiet-zone 2)))
  (def path @"")
  (for y 0 matrix-size
    (for x 0 matrix-size
      (when (module code x y)
        (buffer/push path
                     "M" (string (+ x quiet-zone)) " " (string (+ y quiet-zone))
                     "h1v1h-1z"))))
  [:svg
   {:xmlns "http://www.w3.org/2000/svg"
    :viewBox (string "0 0 " image-size " " image-size)
    :shape-rendering "crispEdges"
    :role "img"}
   [:rect {:width image-size :height image-size :fill "#fff"}]
   [:path {:d (string path) :fill "#000"}]])
