(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["jhydro"
                 "https://git.sr.ht/~pepe/janetls"
                 {:url "https://github.com/pepe/spork"
                  :tag "a306ac22358d7b801d7d290f43369d93be89b779"}])

(declare-source :source ["gp"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["cjanet/fuzzy.janet"])

(declare-native
  :name "gp/net/curi"
  :source @["cjanet/curi.janet"])
