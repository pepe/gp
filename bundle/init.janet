(use spork/declare-cc spork/path spork/sh)

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

(declare-binscript
  :main "bin/gpgen"
  :is-janet true
  :auto-shebang true)

(unless (= (os/which) :windows)
  (declare-native
    :name "gp/term"
    :source @["cjanet/term.janet"])

  (declare-binscript
    :main "bin/gpf"
    :is-janet true
    :auto-shebang true))

