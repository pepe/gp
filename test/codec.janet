(use spork/test jhydro)
(import /build/gp/codec)
(start-suite "Documentation")
(assert-docs "/build/gp/codec")
(end-suite)
(start-suite "base64")
(assert (= (codec/base64/encode "Ahoj") "QWhvag==") "encode")
(assert (= (codec/base64/decode "QWhvag==") "Ahoj") "decode")
(assert (= (codec/base64/encode (string/repeat "a" 100))
           "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYQ=="))
(assert (= (codec/base64/decode "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYQ==")
           (string/repeat "a" 100)) "decode")
(assert (codec/base64/encode (string/repeat "a" 1000000)))
(assert (codec/base64/decode (string/repeat "a" 1000000)))
(end-suite)

(start-suite "picohash")
(assert (= "E|\xECM\x12\xA2\xEF\xE9\xC8\xEBF\xB0\xBA\xF6z)"
           (codec/picohash/md5 "Ahoj")) "md5")
(assert (= "[\xDA\x92r\x08\xC5\x10\xB9\xF7\x0E\xE9\xAB\x8B\x8E\xEC\xB7\xB1HR\xB4"
           (codec/picohash/sha1 "Ahoj")) "sha1")
(assert (= "o\xC3\x8A\xB7\xBF\xFF\xDD\xAB|5\xE9\xD0I~\xB0xU\xF3\xD01#I\xFD\xC3\x1C\x95\xCC\x05"
           (codec/picohash/sha224 "Ahoj")) "sha224")
(assert (= "\xF2>h\x07\xB3\xFB\v\xE0\xEA\x99\x9E\xA8\xCB\x88\xA3\xE9M\xC3Y\xC8B0F\x1F\x97a\xEF\xACW\xDC\xB0\x81"
           (codec/picohash/sha256 "Ahoj")) "sha256")
(end-suite)

(start-suite "picohash/hmac")
(assert (= "~<D\xA6\x1A\x02Y\xCDJ\xE8j\x84\xC4\xE6\x99d"
           (codec/picohash/hmac/md5 "secret" "Ahoj")))
(assert (= "\x97\xC9/\xAAiM\x97\r\xC2t\x96\xCB[\xCC\x19\x8E\xD8\x04\x9E\xB9"
           (codec/picohash/hmac/sha1 "secret" "Ahoj")) "sha1")
(assert (= "\xEF\xB9\xF5\xDD\xEF\xE7\x19,\xB4\xD5\xA717z\xFA\xC2\xFB\xFAA\xAD\xF2\x82\xA1\xEB\x9C\"\xBD\xFC"
           (codec/picohash/hmac/sha224 "secret" "Ahoj")) "sha224")
(assert (= "^=\x07*3Y\xB6\x80-\xF4[\xE6\xE7\xAA\xF0\x1A\xBC\xBC\xEB\\6\xC0\xCBDS~\x1D)\xD8\x82\x1D6"
           (codec/picohash/hmac/sha256 "secret" "Ahoj")) "sha256")

(end-suite)
