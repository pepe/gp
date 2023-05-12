(use spork/cjanet)

(include <janet.h>)
(include `"../src/base64.h"`)
(include `"../src/picohash.h"`)

(def md5-hex-length 32)
(def sha1-hex-length 40)
(def sha256-hex-length 64)

(defn- cstr [name]
  ~(def (,(symbol '*c name) (const uint8_t))
     (janet_string (. ,name bytes) (. ,name len))))

(cfunction
  decode
  "Decodes BASE64"
  [str:bytes] -> Janet
  ,(cstr 'str)
  (def (b64l int) (Base64decode_len cstr))
  (def (out (array char b64l)))
  (def (outl int) (Base64decode out cstr))
  (return (janet_stringv out outl)))

(module-entry "codec")
