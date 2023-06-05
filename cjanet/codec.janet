(use spork/cjanet)

(include <janet.h>)
(include `"../src/base64.h"`)
(include `"../src/picohash.h"`)

(def md5-hex-length 32)
(def sha1-hex-length 40)
(def sha256-hex-length 64)

(cfunction
  base64/encode
  "Encodes BASE64"
  [str:string] -> Janet
  (def (len int) (janet_string_length str))
  (def (b64l int) (Base64encode_len len))
  (def (out (array char b64l)))
  (def (outl int) (Base64encode out str len))
  (return (janet_stringv out (- outl 1))))

(cfunction
  base64/decode
  "Decodes BASE64"
  [str:string] -> Janet
  (def (b64l int) (Base64decode_len str))
  (def (out (array char b64l)))
  (def (outl int) (Base64decode out str))
  (return (janet_stringv out outl)))

(module-entry "codec")
