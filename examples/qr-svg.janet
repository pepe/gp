(import gp/qr)
(import spork/htmlgen)

(def code (qr/encode "https://example.org"))
(print (htmlgen/html (qr/svg code)))
