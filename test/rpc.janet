(use spork/test spork/misc)
(import ../gp/net/server)
(use ../gp/net/rpc)

(start-suite "RPC documentation")
(assert-docs "../gp/net/rpc")
(end-suite)

(def psk "helohelohelohelohelohelohelohelo")

(start-suite "on-connection")
(assert (function? (on-connection @{:hello (fn hello [_] "hello")
                                    :psk psk}))
        "on-connection function")
(assert (match (protect (on-connection {}))
          [false "Handler is not valid"] true
          false) "wrong type handler")
(assert (match (protect (on-connection @{}))
          [false "Handler is not valid"] true
          false) "empty handler")
(end-suite)

(start-suite "Supervisor on-connection")
(def entered (ev/chan 8))
(def release (ev/chan 8))
(ev/spawn
  (def sc (ev/chan))
  (def handling (on-connection @{:hello (fn hello [_] "hello")
                                 :echo (fn [_ value] (ev/sleep 0.01) value)
                                 :fail (fn [_] (error "remote failure"))
                                 :held (fn [_ value]
                                         (ev/give entered value)
                                         (ev/take release)
                                         value)
                                 :psk psk}))
  (server/start sc "localhost" 9999)
  (supervisor sc handling))

(ev/sleep 0.001) # give server time to settle

(var test-client
  (client "localhost" 9999 "pepe" psk))

(assert test-client "client created")

(assert
  (= (:hello test-client) "hello")
  "hello fn")

(assert-error
  "not supported fn"
  (:bye test-client))

(assert
  (:close test-client)
  "close test-client")

(assert-error
  "already closed test-client"
  (:hello test-client))

(assert
  (:reopen test-client)
  "reopen test-client")

# Re-opening a client that still holds a line lets the old one go. It used
# to overwrite the stream and say nothing, which sends no close: the peer's
# fiber stayed parked on a socket nobody would speak on again, and this
# side kept the descriptor until the collector reached it. Cheap once, and
# a registration renewed on a beat does it every minute.
(let [old (test-client :stream)]
  (assert (:open test-client) "open a client that already has a line")
  (assert (not= old (test-client :stream)) "and it holds a new one")
  (assert (match (protect (:write old "x"))
            [false _] true
            false)
          "while the line it let go of is closed"))
(assert (= (:hello test-client) "hello") "and still answers on the new one")

# One client has one encrypted message counter and one framing buffer.
# Concurrent callers must own the whole send/receive exchange, not merely
# the write. Before serialization the second caller could take the first
# reply while the first caller remained parked indefinitely.
(def done (ev/chan 32))
(defn call-async [tag body]
  (ev/go (fn [] (ev/give done [tag (protect (body))]))))
(defn result [] (ev/with-deadline 2 (ev/take done)))
(for i 0 12
  (call-async i (fn [] (:echo test-client i))))
(def answers @{})
(repeat 12
  (def [tag reply] (result))
  (put answers tag reply))
(assert (= 12 (length answers)) "all overlapping calls complete")
(for i 0 12
  (assert (= [true i] (answers i)) "each caller receives its own reply"))

(assert-error "remote application error propagates" (:fail test-client))
(assert (= "hello" (:hello test-client)) "remote error releases lock without breaking connection")

# Closing interrupts the owner and lets a queued caller fail, rather than
# making shutdown wait behind an RPC which may never answer.
(call-async :closed-owner (fn [] (:held test-client :closing)))
(assert (= :closing (ev/take entered)) "held call reached server")
(def independent (client "localhost" 9999 "independent" psk))
(assert (= "hello" (ev/with-deadline 1 (:hello independent)))
        "a held client does not block a different client")
(:close independent)
(call-async :closed-waiter (fn [] (:hello test-client)))
(ev/sleep 0.01)
(:close test-client)
(repeat 2
  (assert (= false (first (last (result)))) "close releases active and queued calls"))
(ev/give release true)
(:open test-client)
(assert (= "hello" (:hello test-client)) "open works after interrupted calls")

# Cancellation after sending invalidates the stream: its late reply must
# never become a later caller's answer. A cancelled waiter, by contrast,
# has not touched the stream and must not release somebody else's lock.
(def owner (call-async :cancelled-owner (fn [] (:held test-client :cancelling))))
(assert (= :cancelling (ev/take entered)) "cancellable owner reached server")
(def waiter (call-async :cancelled-waiter (fn [] (:hello test-client))))
(ev/sleep 0.01)
(ev/cancel waiter :test-cancel)
(assert (= [:cancelled-waiter [false :test-cancel]] (result)) "cancelled waiter leaves owner alone")
(assert (test-client :stream) "waiting cancellation preserves connection")
(ev/cancel owner :test-cancel)
(assert (= [:cancelled-owner [false :test-cancel]] (result)) "cancelled owner returns error")
(assert (nil? (test-client :stream)) "cancelled exchange discards its stream")
(ev/give release true)
(:open test-client)
(assert (= "hello" (:hello test-client)) "lock released after owner cancellation")

# Opening and remote calls use the same client lock. A method closure saved
# from an older connection must fail after replacement, not use its buffers.
(def old-hello (test-client :hello))
(call-async :before-open (fn [] (:held test-client :opening)))
(assert (= :opening (ev/take entered)) "call precedes reopen")
(call-async :open (fn [] (:open test-client) :opened))
(ev/sleep 0.01)
(ev/give release true)
(assert (= [:before-open [true :opening]] (result)) "open lets active exchange finish")
(assert (= [:open [true :opened]] (result)) "queued open completes")
(assert-error "old generation closure rejected" (old-hello test-client))
(assert (= "hello" (:hello test-client)) "new generation remains usable")

(put test-client :timeout 0.03)
(def began (os/clock))
(assert-error "a direct call has a default deadline" (:held test-client :deadline))
(assert (< (- (os/clock) began) 1) "timeout is bounded without an outer deadline")
(assert (nil? (test-client :stream)) "timed-out exchange cannot contaminate the next call")
(assert (= :deadline (ev/take entered)))
(ev/give release true)
(put test-client :timeout 8)
(:open test-client)
(assert (= "hello" (:hello test-client)))

(def failed-client (make Client :host "localhost" :port 9999 :name "retry"
                        :psk "badybadybadybadybadybadybadybady"))
(assert-error "failed handshake propagates" (:open failed-client))
(assert (nil? (failed-client :stream)) "failed handshake discards stream")
(put failed-client :psk psk)
(:open failed-client)
(assert (= "hello" (:hello failed-client)) "failed handshake releases setup lock")
(:close failed-client)

(assert-error
  "bad psk"
  (client
    "localhost"
    9999 "pepe"
    "badybadybadybadybadybadybadybady"))
(end-suite)

(start-suite "Server")
(assert (= :core/channel
           (type (server @{:hello (fn hello [_] "hello") :psk psk}
                         "localhost" 9998)))
        "returns channel")
(ev/sleep 0.001) # give server time to settle
(def test-client
  (client "localhost" 9998 "pepes" psk))
(assert
  (= (:hello test-client) "hello")
  "hello fn")
(end-suite)
(os/exit)
