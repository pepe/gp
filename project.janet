(declare-project
  :name "gp"
  :author "Josef Pospíšil <josef.pospisil@laststar.eu>"
  :description "Good Place library"
  :license "MIT"
  :repo "https://git.sr.ht/~pepe/gp"
  :url "https://good-place.org/"
  :dependencies ["spork" "https://git.sr.ht/~pepe/janet-uri"])

(declare-source :source ["gp"])

(add-loader)
(import /fzy-reduced)

(task "fzy_reduced.c" []
      (fzy-reduced/render "fzy_reduced.c"))

(declare-native
  :name "fuzzy"
  :source @["fzy_reduced.c"])
