(use spork/declare-cc spork/path spork/sh spork/cc)

(declare-project :name "gp")

(declare-source :source ["gp"])

(declare-native
  :name "gp/codec"
  :source @["cjanet/codec.janet"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["cjanet/fuzzy.janet"])

(declare-native
  :name "gp/net/curi"
  :source @["cjanet/curi.janet"])

(declare-native
  :name "gp/qr-native"
  :source @["cjanet/qr-codegen.janet" "src/qrcodegen.c"])

(eval (parse (string "(do\n" (slurp "compute-build.janet") "\n)")))

(eval (parse (string "(do\n" (slurp "llm-build.janet") "\n)")))

