(use spork/cjanet)

# helper functions

(defn- set-bufout-inc-bor [& expr]
  ~(set '"*(bufout++)" (cast "unsigned char" (bor ,;expr))))

(defn- set-p-inc-basis [expr]
  ~(set '"*(p++)" (aref basis_64 ,expr)))

# C generation

(include <janet.h>)

(include `"../src/picohash.h"`)

(declare (pr2six (array "static const unsigned char" 256) :static)
         (array ,;(seq [_ :range [0 43]] 64) 62 ,;(seq [_ :range [0 3]] 64) 63
                ,;(seq [i :range [52 62]] i) ,;(seq [_ :range [0 7]] 64)
                ,;(seq [i :range [0 26]] i) ,;(seq [_ :range [0 6]] 64)
                ,;(seq [i :range [26 52]] i) ,;(seq [_ :range [0 133]] 64)))

(cfunction
  base64/decode
  "Decodes BASE64"
  [str:string] -> Janet
  (def nbytesdecoded:int)
  (def (*bufin "register const unsigned char"))
  (def (*bufout "register unsigned char"))
  (def (nprbytes "register int"))
  (set bufin (cast "const unsigned char *" str))
  (while (<= (aref pr2six '"*(bufin++)") 63))
  (set nprbytes (- bufin (cast "const unsigned char *" str) 1))
  (set nbytesdecoded (* (/ (+ nprbytes 3) 4) 3))
  (def (*out char) (janet_smalloc (* (sizeof char) nbytesdecoded)))
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
                         '(>> (aref pr2six (aref bufin 1)) 4))
    (if (> nprbytes 2)
      ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 1)) 4)
                           '(>> (aref pr2six (aref bufin 2)) 2))
      (if (> nprbytes 3)
        ,(set-bufout-inc-bor '(<< (aref pr2six (aref bufin 2)) 6)
                             '(aref pr2six (aref bufin 3))))))

  (set nbytesdecoded (- nbytesdecoded (band (- 4 nprbytes) 3)))
  (def res:Janet (janet_stringv out nbytesdecoded))
  (janet_sfree out)
  (return res))

(declare (basis_64 (array "static const char"))
         "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

(cfunction
  base64/encode
  "Encodes BASE64"
  [str:string] -> Janet
  (def len:int (janet_string_length str))
  (def olen:int (+ (* (/ (+ len 2) 3) 4) 1))
  (def (*out char) (janet_smalloc (* (sizeof char) olen)))
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

(defmacro picohashes
  "Generates picohash wrapping functions"
  [& phs]
  (catseq [ph :in phs
           :let [uph (string/ascii-upper ph)
                 piph (symbol 'picohash_init_ ph)
                 dlph (symbol 'PICOHASH_ uph '_DIGEST_LENGTH)
                 tail ~((picohash_update &ctx str (janet_string_length str))
                         (def (buf (array uint8_t ,dlph)))
                         (picohash_final &ctx buf)
                         (return (janet_stringv buf ,dlph)))]]
          ~[(cfunction
              ,(symbol 'picohash/ ph)
              ,(string "Hashes `str` with picohash's " ph)
              [str:string] -> Janet
              (def ctx:picohash_ctx_t)
              (,piph &ctx)
              ,;tail)
            (cfunction
              ,(symbol 'picohash/hmac/ ph)
              ,(string "Hashes `str` with `key` with picohash's hmac " ph)
              [key:string str:string] -> Janet
              (def ctx:picohash_ctx_t)
              (picohash_init_hmac &ctx ,piph key (janet_string_length key))
              ,;tail)]))

(picohashes md5 sha1 sha224 sha256)

(module-entry "codec")
