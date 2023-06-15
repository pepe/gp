# All the code is blatantly stolen from andrewchambers/janet-uri
# and converted to cjanet
(use spork/cjanet)

(include <janet.h>)
(include <ctype.h>)
(include <stdio.h>)
(include <stdlib.h>)
(include <string.h>)

(defn- in-range [c b e]
  ~(and (>= ,c ,(in b 0))
        (<= ,c ,(in e 0))))

(function
  decode_nibble :static
  [(b uint8_t)] -> int
  (cond
    ,(in-range 'b "0" "9")
    (return (- b ,(chr "0")))
    ,(in-range 'b "a" "f")
    (return (- (+ 10 b) ,(chr "a")))
    ,(in-range 'b "A" "F")
    (return (- (+ 10 b) ,(chr "A")))
    (return 0)))

(function
  unreserved :static
  [(c uint8_t)] -> int
  (return (or ,(in-range 'c "0" "9")
              ,(in-range 'c "a" "f")
              ,(in-range 'c "A" "F")
              (== c ,(chr "-"))
              (== c ,(chr "_"))
              (== c ,(chr "."))
              (== c ,(chr "~")))))

(declare (*chartab char) :static "0123456789abcdef")

(cfunction
  escape :static
  "uri escape str"
  [str:string] -> Janet
  (def len:size_t (janet_string_length str))
  (def nwritten:size_t 0)
  (def *tmp:uint8_t NULL)
  (set tmp (janet_smalloc (* len 3)))
  (def i:size_t 0)
  (while (< i len)
    (def c:uint8_t (aref str i))
    (if (unreserved c)
      (do
        (set (aref tmp nwritten) c)
        (++ nwritten))
      (do
        (set (aref tmp nwritten) (literal "'%'"))
        (++ nwritten)
        (set (aref tmp nwritten) (aref chartab (brshift (band c 0xf0) 4)))
        (++ nwritten)
        (set (aref tmp nwritten) (aref chartab (band c 0x0f)))
        (++ nwritten)))
    (++ i))

  (def escaped:Janet (janet_stringv tmp nwritten))
  (janet_sfree tmp)
  (return escaped))

(cfunction
  unescape :static
  "uri unescape str"
  [str:string] -> Janet
  (def len:size_t (janet_string_length str))
  (def nwritten:size_t 0)
  (def *tmp:uint8_t NULL)
  (set tmp (janet_smalloc (* len 3)))
  (def i:size_t 0)
  (def st:int 0)
  (def nb1:uint8_t)
  (def nb2:uint8_t)
  (while (< i len)
    (def c:uint8_t (aref str i))
    (switch
      st
      0 (do
          (switch
            c
            ,(chr "%") (do (set st 1) (break))
            (do
              (set (aref tmp nwritten) c)
              (++ nwritten)))
          (break))
      1 (do
          (set st 2)
          (set nb1 (decode_nibble c))
          (break))
      2 (do
          (set st 0)
          (set nb2 (decode_nibble c))
          (set (aref tmp nwritten) (bor (blshift nb1 4) nb2))
          (++ nwritten)
          (break))
      (abort))
    (++ i))
  (def unescaped:Janet (janet_stringv tmp nwritten))
  (janet_sfree tmp)
  (return unescaped))

(module-entry "curi")
