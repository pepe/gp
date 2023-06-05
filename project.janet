(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["spork" "jhydro"
                 "https://git.sr.ht/~pepe/janetls"])

(declare-source :source ["gp"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["cjanet/fuzzy.janet"])

(declare-native
  :name "gp/net/curi"
  :source @["cjanet/curi.janet"])
