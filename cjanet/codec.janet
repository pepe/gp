(use spork/cjanet)

(include <janet.h>)

(include `"../src/picohash.h"`)

(declare (pr2six (array "static const unsigned char" 256) :static)
         (array ,;(seq [_ :range [0 43]] 64) 62 ,;(seq [_ :range [0 3]] 64) 63
                ,;(seq [i :range [52 62]] i) ,;(seq [_ :range [0 7]] 64)
                ,;(seq [i :range [0 26]] i) ,;(seq [_ :range [0 6]] 64)
                ,;(seq [i :range [26 52]] i) ,;(seq [_ :range [0 133]] 64)))

(defn- set-bufout-inc-bor [& expr]
  ~(set '"*(bufout++)" (cast "unsigned char" (bor ,;expr))))

(cfunction
  base64/decode
  "Encodes BASE64"
  [str:string] -> Janet
  (def nbytesdecoded:int)
  (def (*bufin "register const unsigned char"))
  (def (*bufout "register unsigned char"))
  (def (nprbytes "register int"))
  (set bufin (cast "const unsigned char *" str))
  (while (<= (aref pr2six '"*(bufin++)") 63))
  (set nprbytes (- (- bufin (cast "const unsigned char *" str)) 1))
  (set nbytesdecoded (* (/ (+ nprbytes 3) 4) 3))
  (def (*out char) (janet_smalloc nbytesdecoded))
  (set bufout (cast "unsigned char *" out))
  (set bufin (cast "const unsigned char *" str))

  (while (> nprbytes 4)
    ,(set-bufout-inc-bor '(<< (aref pr2six *bufin) 2)
                         '(>> (aref pr2six (aref bufin 1)) 4))
    ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 1)) 4)
                         '(>> (aref pr2six (aref bufin 2)) 2))
    ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 2)) 6)
                         '(aref pr2six (aref bufin 3)))
    (set bufin (+ bufin 4))
    (set nprbytes (- nprbytes 4)))
  (if (> nprbytes 1)
    ,(set-bufout-inc-bor '(<< (aref pr2six *bufin) 2)
                         '(>> (aref pr2six (aref bufin 1)) 4)))
  (if (> nprbytes 2)
    ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 1)) 4)
                         '(>> (aref pr2six (aref bufin 2)) 2)))
  (if (> nprbytes 3)
    ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 2)) 6)
                         '(aref pr2six (aref bufin 3))))
  (set nbytesdecoded (- nbytesdecoded (band (- 4 nprbytes) 3)))
  (def res:Janet (janet_stringv out nbytesdecoded))
  (janet_sfree out)
  (return res))

(declare (basis_64 (array "static const char"))
         "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(defn- set-p-inc-basis [expr]
  ~(set '"*(p++)" (aref basis_64 ,expr)))

(cfunction
  base64/encode
  "Encodes BASE64"
  [str:string] -> Janet
  (def len:int (janet_string_length str))
  (def olen:int (+ (* (/ (+ len 2) 3) 4) 1))
  (def (*out char) (janet_smalloc olen))
  (def *p:char)
  (set p out)
  (def i:int 0)
  (while (< i (- len 2))
    ,(set-p-inc-basis '(band (>> (aref str i) 2) 0x3F))
    ,(set-p-inc-basis '(bor (<< (band (aref str i) 0x3) 4)
                            (cast int (>> (band (aref str (+ i 1)) 0xF0) 4))))
    ,(set-p-inc-basis '(bor (<< (band (aref str (+ i 1)) 0xF) 2)
                            (cast int (>> (band (aref str (+ i 2)) 0xC0) 6))))
    ,(set-p-inc-basis '(band (aref str (+ i 2)) 0x3F))
    (set i (+ i 3)))
  (if (< i len)
    (do
      ,(set-p-inc-basis '(band (>> (aref str i) 2) 0x3F))
      (if (== i (- len 1))
        (do
          ,(set-p-inc-basis '(<< (band (aref str i) 0x3) 4))
          (set '"*(p++)" ,(chr "=")))
        (do
          ,(set-p-inc-basis '(bor (<< (band (aref str i) 0x3) 4)
                                  (cast int (>> (band (aref str (+ i 1)) 0xF0) 4))))
          ,(set-p-inc-basis '(<< (band (aref str (+ i 1)) 0xF) 2))))
      (set '"*(p++)" ,(chr "="))))
  (def res:Janet (janet_stringv out (- p out)))
  (janet_sfree out)
  (return res))

(cfunction
  hash/md5
  "Hashes `str` with md5"
  [str:string] -> Janet
  (def ctx:picohash_ctx_t)
  (def *buf:JanetBuffer (janet_buffer PICOHASH_MD5_DIGEST_LENGTH))
  (def len:int (janet_string_length str))
  (picohash_init_md5 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)
  (return (janet_stringv (-> buf data) PICOHASH_MD5_DIGEST_LENGTH)))

(cfunction
  hash/sha1
  "Hashes `str` with sha1"
  [str:string] -> Janet
  (def ctx:picohash_ctx_t)
  (def *buf:JanetBuffer (janet_buffer PICOHASH_SHA1_DIGEST_LENGTH))
  (def len:int (janet_string_length str))
  (picohash_init_sha1 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)
  (return (janet_stringv (-> buf data) PICOHASH_SHA1_DIGEST_LENGTH)))

(cfunction
  hash/sha256
  "Hashes `str` with sha256"
  [str:string] -> Janet
  (def ctx:picohash_ctx_t)
  (def *buf:JanetBuffer (janet_buffer PICOHASH_SHA256_DIGEST_LENGTH))
  (def len:int (janet_string_length str))
  (picohash_init_sha256 &ctx)
  (picohash_update &ctx str len)
  (picohash_final &ctx buf->data)
  (return (janet_stringv (-> buf data) PICOHASH_SHA256_DIGEST_LENGTH)))

(module-entry "codec")
