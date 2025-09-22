(use spork/declare-cc spork/path spork/sh)

(declare-project :name "gp")

(declare-source :source ["gp"])

(defn codegen
  "Generates to `out-path` from code in `in-path`"
  [in-path out-path]
  (with [f (file/open out-path :wbn)]
    (def env (make-env))
    (put env :out f)
    (dofile in-path :env env)))

(def mods ["codec" "fuzzy" "curi" "term"])

(rule :pre-build []
      (loop [m :in mods
             :let [in-path (join "cjanet" (string m ".janet"))
                   out-path (join "_build" (string m ".janet.c"))]]
        (codegen in-path out-path)))

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

(def relp (join "_build" "release"))
(def testp "_test")

(rule :pre-check []
      (each d ["data" "net"] (create-dirs (join testp d)))
      (loop [f :in (os/dir relp)
             :let [fp (join relp f)
                   of (join testp (string/replace-all "___" "/" f))]
             :when (= :file (os/stat fp :mode))]
        (copy-file fp of)))

(rule :post-check []
      (ev/sleep 0.1)
      (rm-readonly testp))

(rule :post-install []
      (loop [m :in mods
             :let [out-path (join "_build" (string m ".janet.c"))]]
        (os/rm out-path)))
