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
(start-suite "hash")
(assert (= "E|\xECM\x12\xA2\xEF\xE9\xC8\xEBF\xB0\xBA\xF6z)"
           (codec/hash/md5 "Ahoj")))
(assert (= "[\xDA\x92r\x08\xC5\x10\xB9\xF7\x0E\xE9\xAB\x8B\x8E\xEC\xB7\xB1HR\xB4"
           (codec/hash/sha1 "Ahoj")) "sha1")

(assert (= "\xF2>h\x07\xB3\xFB\v\xE0\xEA\x99\x9E\xA8\xCB\x88\xA3\xE9M\xC3Y\xC8B0F\x1F\x97a\xEF\xACW\xDC\xB0\x81"
           (codec/hash/sha256 "Ahoj")) "sha256")

(end-suite)
