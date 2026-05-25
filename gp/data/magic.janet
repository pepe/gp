(use ./navigation ./schema)

(defmacro wand
  "Creates a traversal function from a literal path."
  [& path]
  (def tag (keyword (gensym)))
  (def skip (gensym))
  (var gated false)
  (var gate-num 0)
  (var safe false)
  (var tracing false)
  (var ret nil)
  (var trace-num 0)
  (defn trace-point [point]
    (++ trace-num)
    (def [l c] (tuple/sourcemap (dyn *macro-form* ())))
    (def cf (dyn *current-file*))
    (def where
      (if cf
        (string/format "trace [%s]" cf)
        "trace"))
    (with-syms [base]
      ~(fn ,(make-name 'trace trace-num point) [,base]
         (eprintf "%s after point %q base is:\n%q \n"
                  ,where ,point ,base)
         ,base)))
  (defn gate? [g]
    (or
      (dictionary? g)
      (array? g)
      (and (tuple? g)
           (= :brackets (tuple/type g)))))
  (defn gate [g]
    (set gated true)
    (set gate-num (+ gate-num 1))
    (def pg (if (dictionary? g) [g] g))
    (def dflt ret)
    (with-syms [base]
      ~(fn ,(make-name 'gate gate-num) [,base]
         (if ((validator ,;pg) ,base)
           ,base
           (return ,tag ,dflt)))))
  (defn getter [g]
    (with-syms [base]
      ~(fn ,(make-name 'get g) [,base]
         (get ,base ,g))))
  (defn prepare [p]
    (match p
      ['<> 'escape] (let [dflt ret]
                      (set gated true) ~(return ,tag ,dflt))
      ['<> 'maybe] (gate [truthy?])
      ['<> 'safe] (do (set safe true) skip)
      ['<> 'reset]
      (do
        (set safe false)
        (set tracing false)
        (set ret nil) skip)
      ['<> 'trace] (do (set tracing true) skip)
      ['<> 'default value] (do (set ret value) skip)
      ['<> c] (maclintf :error "Unknown vigil %j" c)
      (f (fn? f)) f
      (g (gate? g)) (gate g)
      (g (idempotent? g)) (getter g)
      p))
  (def ppath @[])
  (loop [point :in path
         :let [ppoint (prepare point)]
         :when ((?neq skip) ppoint)]
    (array/push ppath ppoint)
    (if safe (array/push ppath (gate [truthy?])))
    (if tracing (array/push ppath (trace-point point))))
  (def nav ~(,traverse ,;ppath))
  (if gated
    (with-syms [data]
      ~(fn wand-traverse [,data]
         (prompt ,tag (,nav ,data))))
    nav))

(def =<> :macro "wand alias" wand)
