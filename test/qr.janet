(use spork/test jhydro)
(import gp/qr)
(import spork/htmlgen)

(start-suite "QR documentation")
(assert-docs "gp/qr")
(end-suite)

(start-suite "QR native boundary")

(def short (qr/encode "https://example.org"))
(assert (= 25 (qr/size short)) "expected stable URL matrix size")
(assert (qr/module short 0 0) "top-left finder module is dark")
(assert-not (qr/module short 7 0) "separator beside top-left finder is light")
(def explicit-medium (qr/encode "https://example.org" :ecc :medium))
(assert
  (deep=
    (seq [y :range [0 (qr/size short)]
          x :range [0 (qr/size short)]]
      (qr/module short x y))
    (seq [y :range [0 (qr/size explicit-medium)]
          x :range [0 (qr/size explicit-medium)]]
      (qr/module explicit-medium x y)))
  "default error correction is :medium")

(each ecc [:low :medium :quartile :high]
  (def code (qr/encode "correction level" :ecc ecc))
  (assert (>= (qr/size code) 21) (string "encode " ecc)))

(assert (qr/encode "") "empty payload")
(assert (qr/encode "Příliš žluťoučký kůň") "UTF-8 payload")
(assert-error "payload type" (qr/encode 123))
(assert-error "unknown option" (qr/encode "x" :wat true))
(assert-error "unsupported correction level" (qr/encode "x" :ecc :extreme))
(assert-error "oversized payload" (qr/encode (string/repeat "x" 8000)))
(assert-error "invalid QR value" (qr/size :not-a-code))
(assert-error "non-integer coordinate" (qr/module short 1.5 0))
(assert-error "negative coordinate" (qr/module short -1 0))
(assert-error "excessive coordinate" (qr/module short (qr/size short) 0))

(gccollect)
(assert (qr/module short 0 0) "QR object survives garbage collection")
(for i 0 100
  (qr/encode (string "cycle-" i))
  (gccollect))

(end-suite)

(start-suite "QR SVG")

(def graphic (qr/svg short))
(def graphic-again (qr/svg short))
(assert (deep= graphic graphic-again) "deterministic SVG structure")
(assert (= "0 0 33 33" (get-in graphic [1 :viewBox])) "four-module quiet zone")
(assert (= "#fff" (get-in graphic [2 1 :fill])) "white background")
(assert (= "#000" (get-in graphic [3 1 :fill])) "black path")
(assert (string? (get-in graphic [3 1 :d])) "one path contains dark modules")
(def path-data (get-in graphic [3 1 :d]))
(var path-has-control-byte false)
(each byte path-data
  (when (or (< byte 32) (= byte 127))
    (set path-has-control-byte true)))
(assert-not path-has-control-byte "path contains no XML control bytes")
(def rendered-svg (string (htmlgen/html graphic)))
(assert (string/find "<svg" rendered-svg) "htmlgen renders SVG")
(assert (string/find `xmlns="http://www.w3.org/2000/svg"` rendered-svg)
        "standalone SVG namespace")

(end-suite)
