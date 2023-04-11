(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["jhydro" "jpm"
                 "https://git.sr.ht/~pepe/janetls"
                 "https://git.sr.ht/~pepe/janet-uri"
                 "https://github.com/janet-lang/spork"])

(declare-source :source ["gp"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["fzy-reduced.janet"])
