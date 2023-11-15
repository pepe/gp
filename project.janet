(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["spork" "jhydro"])

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
