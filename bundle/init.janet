(use spork/declare-cc)
(import spork/path)

(declare-project
  :name "gp"
  :dependencies ["spork" "jhydro"])

(declare-source :source ["gp"])

(loop [m :in ["codec" "fuzzy" "curi" "term"]
         :let [in-path (path/join "cjanet" (string m ".janet"))
               out-path (path/join "_build" (string m ".janet.c"))]]
    (with [f (file/open out-path :wbn)]
      (def env (make-env))
      (put env :out f)
      (dofile in-path :env env)))  

(declare-native
  :name "gp/codec"
  :source @["_build/codec.janet.c"])

(declare-native
  :name "gp/data/fuzzy"
  :source @["_build/fuzzy.janet.c"])

(declare-native
  :name "gp/net/curi"
  :source @["_build/curi.janet.c"])

(declare-binscript
  :main "bin/gpgen"
  :is-janet true
  :auto-shebang true)

(unless (= (os/which) :windows)
  (declare-native
    :name "gp/term"
    :source @["_build/term.janet.c"])

  (declare-binscript
    :main "bin/gpf"
    :is-janet true
    :auto-shebang true))
