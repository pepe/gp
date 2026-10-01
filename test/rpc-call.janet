(use spork/test)
(import gp/net/rpc)
(start-suite :retry-safety)
(def calls @[])
(def client
  @{:stream :old
    :read (fn [self] (array/push calls :old) (put self :stream nil) (error "closed"))
    :open (fn [self]
            (put self :stream :new)
            (put self :read (fn [_] (array/push calls :new) :latest)))})
(assert (= :latest (rpc/call client :read [] true)))
(assert (= [:old :new] (tuple ;calls)) "retry resolves the new method, never its old closure")
(put client :write (fn [self] (put self :stream nil) (error "lost reply")))
(assert-error "mutation is never retried implicitly" (rpc/call client :write []))
(assert (nil? (client :stream)))
(end-suite)
