(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["spork" "jhydro"
                 "https://git.sr.ht/~pepe/janetls"
                 "https://git.sr.ht/~pepe/janet-uri"])

(declare-source :source ["gp" "fzycode.janet"])

(add-loader)
(import /fzy-reduced)

(task "fzy_reduced.c" []
      (fzy-reduced/render "fzy_reduced.c"))

(declare-native
  :name "gp/data/fuzzy"
  :source @["fzy_reduced.c"])
