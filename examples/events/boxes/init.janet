# This example shows how you can network servers in the cocoons
# Use spork messaging
(import spork/msg)

(use /gp/events)

# Static UpdateAct that increases the counter in the envelope
(define-update IncreaseCounter [_ envelope]
  (update envelope :counter inc))

# Static EffectAct that prints the envelope
(define-effect PrintEnvelope [_ envelope _]
  (pp envelope))

# Initilize shawn's envelope with the :counter set to zero
(def shawn (make-manager @{:counter 0}))

# Server handler akin to one used in spork/rpc
(defn handler
  "Handler for the server, copied verbatim from the spork/rpc"
  [functions]
  (def keys-msg (keys functions))
  (fn on-connection [stream] (var name "<unknown>")
    (def marshbuf @"")
    (defer (:close stream)
      (def recv (msg/make-recv stream unmarshal))
      (def send (msg/make-send stream marshal))
      (set name (or (recv) (break)))
      (send keys-msg)
      (while (def msg (recv))
        (send
          (protect
            (let [[fnname args] msg
                  f (functions fnname)]
              (if-not f
                (error (string "no function " fnname " supported")))
              (f functions ;args))))))))

(def envelope (shawn :envelope))

# RPC Server akin to one used in spork/rpc
(defn server
  "Run rpc server "
  [port]
  (var has-quit nil)
  (with [s (net/listen "localhost" port)]
    (def run
      (handler
        {:inc (fn [_] (produce IncreaseCounter))
         :print (fn [_] (produce PrintEnvelope) envelope)
         :die (fn [_]
                # Emerge EffectAct from the server
                (produce
                  (make-effect
                    (fn [&] (print "=== RPC server stopped on port " port))))
                (set has-quit (if (> (envelope :counter) 4) :too-hi :ok)))}))
    (while (not has-quit) (run (tracev (net/accept s)))))
  # Return the Cocoon product
  has-quit)

# Dynamic Act for starting a server and printing the log
(defn start-server [&opt port]
  (default port "9999")
  (make-event {:watch (fn [_ _ _]
                        # Give Cocoon to supervisor
                        (producer (server port)))
               :effect (fn [_ _ _]
                         (print "=== RPC server starter on port " port))}))

# Confirm two server starting Acts
(:transact shawn (start-server) (start-server "9998"))

# Print the final envelope and cocoons products
(pp (:await shawn))
(:close (shawn :_thread-flow)) # must be here so shawn does not hang

