(use spork/declare-cc spork/path)

# from the jpm/declare
(defn dofile-codegen
  "Takes the source code and renders it to file (temple, cjanet, etc.)"
  [in-path out-path]
  (with [f (file/open out-path :wbn)]
    (def env (make-env))
    (put env :out f)
    (dofile in-path :env env)))

(declare-project
  :name "gp"
  :dependencies ["spork" "jhydro"])

(declare-source :source ["gp"])

(declare-binscript
  :main "bin/gpgen"
  :is-janet true
  :auto-shebang true)

(each f ["codec" "curi" "fuzzy"]
  (def gsrc (string "_build/" f ".c"))
  (dofile-codegen (string "cjanet/" f ".janet") gsrc)
  (declare-native
    :name (string "gp/data/" f)
    :source @[gsrc]))

(unless (= (os/which) :windows)
  (dofile-codegen "cjanet/term.janet" "_build/term.c")
  (declare-native
    :name "gp/term"
    :source @["_build/term.janet"])

  (declare-binscript
    :main "bin/gpf"
    :is-janet true
    :auto-shebang true))
