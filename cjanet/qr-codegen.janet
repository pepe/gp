(use spork/cjanet spork/path)

(defn- include-src
  # Resolved while generating, when the working directory is the project
  # root. A path relative to the generated C would depend on where the
  # build layout puts it, which is not ours to know.
  [path]
  (abspath path))

(include <janet.h>)
(include <string.h>)
(include ,(include-src "src/qrcodegen.h"))

(typedef
  QRCode
  (named-struct
    QRCode
    size int
    modules (array uint8_t qrcodegen_BUFFER_LEN_MAX)))

(abstract-type QRCode
  :name "gp/qr-code")

(function ecc-level :static
  [ecc:Janet] -> int
  (if (not (janet-checktype ecc JANET_KEYWORD))
    (janet-panic "expected :ecc to be one of :low, :medium, :quartile, or :high"))
  (cond
    (janet-equals ecc (janet-ckeywordv "low"))
    (return qrcodegen_Ecc_LOW)
    (janet-equals ecc (janet-ckeywordv "medium"))
    (return qrcodegen_Ecc_MEDIUM)
    (janet-equals ecc (janet-ckeywordv "quartile"))
    (return qrcodegen_Ecc_QUARTILE)
    (janet-equals ecc (janet-ckeywordv "high"))
    (return qrcodegen_Ecc_HIGH))
  (janet-panic "unsupported QR error-correction level; expected :low, :medium, :quartile, or :high")
  (return qrcodegen_Ecc_MEDIUM))

(cfunction
  encode
  ```
  Encode a UTF-8 string as a QR code. The optional `:ecc` level is one of
  `:low`, `:medium`, `:quartile`, or `:high` and defaults to `:medium`.
  ```
  [payload:string &opt ecc:value=nil] -> *QRCode
  (if (janet-checktype ecc JANET_NIL)
    (set ecc (janet-ckeywordv "medium")))
  (def payload-length:size_t (janet-string-length payload))
  (if (memchr payload 0 payload-length)
    (janet-panic "QR payload must not contain a NUL byte"))
  (def (temp (array uint8_t qrcodegen_BUFFER_LEN_MAX)) nil)
  (def code:*QRCode (janet-abstract QRCode-ATP (sizeof QRCode)))
  (def ok:bool
    (qrcodegen-encodeText
      (cast (* (const char)) payload)
      (addr (aref temp 0))
      (addr (aref code->modules 0))
      (ecc-level ecc)
      qrcodegen_VERSION_MIN
      qrcodegen_VERSION_MAX
      qrcodegen_Mask_AUTO
      false))
  (if (not ok)
    (janet-panic "QR payload is too large to encode"))
  (set code->size (qrcodegen-getSize (addr (aref code->modules 0))))
  (return code))

(cfunction
  size
  "Return the width and height of a QR code's logical module matrix."
  [code:*QRCode] -> int
  (return code->size))

(cfunction
  module
  "Return whether the module at integer coordinates `x`, `y` is dark."
  [code:*QRCode x:int y:int] -> bool
  (if (or (< x 0) (< y 0) (>= x code->size) (>= y code->size))
    (janet-panic "QR module coordinates are outside the matrix"))
  (return (qrcodegen-getModule (addr (aref code->modules 0)) x y)))

(module-entry "_qr")
