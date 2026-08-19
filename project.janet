(use spork/cc)

(declare-project
  ;(-> (slurp "bundle/info.jdn") parse kvs))

(declare-source :source ["gp"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["cjanet/fuzzy.janet"])

(declare-native
  :name "gp/net/curi"
  :source @["cjanet/curi.janet"])

(declare-native
  :name "gp/codec"
  :source @["cjanet/codec.janet"])

(declare-native
  :name "gp/qr-native"
  :source @["cjanet/qr-codegen.janet" "src/qrcodegen.c"])

(eval (parse (string "(do\n" (slurp "compute-build.janet") "\n)")))

(unless (= (os/which) :windows)
  (declare-native
    :name "gp/term"
    :source @["cjanet/term.janet"])

  (declare-binscript
    :main "bin/gpf"
    :is-janet true
    :auto-shebang true))

(declare-binscript
  :main "bin/gpgen"
  :is-janet true
  :auto-shebang true)
