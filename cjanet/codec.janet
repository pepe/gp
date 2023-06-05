(use spork/cjanet)

(include <janet.h>)
(include `"../src/base64.h"`)
(include `"../src/picohash.h"`)


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

(cfunction
  hash/md5
  "Hashes `str` with md5"
  [str:string] -> Janet
  (def (ctx picohash_ctx_t))
  (def (*buf JanetBuffer) (janet_buffer PICOHASH_MD5_DIGEST_LENGTH))

  (def (len int) (janet_string_length str))

  (picohash_init_md5 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)

  (return (janet_stringv (-> buf data) PICOHASH_MD5_DIGEST_LENGTH)))

(cfunction
  hash/sha1
  "Hashes `str` with sha1"
  [str:string] -> Janet
  (def (ctx picohash_ctx_t))
  (def (*buf JanetBuffer) (janet_buffer PICOHASH_SHA1_DIGEST_LENGTH))

  (def (len int) (janet_string_length str))

  (picohash_init_sha1 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)

  (return (janet_stringv (-> buf data) PICOHASH_SHA1_DIGEST_LENGTH)))

(cfunction
  hash/sha256
  "Hashes `str` with sha256"
  [str:string] -> Janet
  (def (ctx picohash_ctx_t))
  (def (*buf JanetBuffer) (janet_buffer PICOHASH_SHA256_DIGEST_LENGTH))

  (def (len int) (janet_string_length str))

  (picohash_init_sha256 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)

  (return (janet_stringv (-> buf data) PICOHASH_SHA256_DIGEST_LENGTH)))

(module-entry "codec")
