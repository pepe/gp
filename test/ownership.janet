(use spork/test)
(import gp/ownership)
(start-suite :exclusive-store-owner)
(def lock-path (string (or (os/getenv "TEMP") "/tmp") "/gp-owner-test-" (os/getpid) ".lock"))
(def first (ownership/acquire lock-path))
(assert-error "second owner is refused" (ownership/acquire lock-path))
(ownership/release first)
(ownership/release first)
(def second (ownership/acquire lock-path))
(ownership/release second)
(def child
  (os/spawn ["janet" "-e"
              (string/format "(import gp/ownership) (def claim (ownership/acquire %q)) (prin \"r\") (file/flush stdout) (ev/sleep 60)" lock-path)]
            :p {:out :pipe :in :pipe}))
(ev/with-deadline 5 (:read (child :out) 1))
(assert-error "a separate process owns the store" (ownership/acquire lock-path))
(os/proc-kill child)
(os/proc-wait child)
(os/proc-close child)
(var recovered nil)
# TerminateProcess is asynchronous; the kernel claim remains authoritative
# even on runtimes that close the process handle before proc-wait.
(ev/with-deadline 2
  (while (not recovered)
    (def [ok claim] (protect (ownership/acquire lock-path)))
    (if ok (set recovered claim) (ev/sleep 0.005))))
(ownership/release recovered)
(assert (os/stat lock-path) "stable lock inode is preserved between owners")
(os/rm lock-path)
(end-suite)
