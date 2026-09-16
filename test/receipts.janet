(use spork/test)
(import ../gp/events :prefix "")

(start-suite :applied-command-receipts)
(def s @{:value 0})
(def results @[])
(def manager (make-manager s (fn [&])))
(:transact manager
  (make-watch
    (producer
      (array/push results
        (produce/applied [(make-watch [(make-update (fn [_ state] (put state :value 1)))])]))
      (array/push results (s :value))
      (array/push results
        (protect (produce/applied
          [(make-effect (fn [&] (error "write failed")))
           (make-update (fn [_ state] (put state :value 2)))])))
      (array/push results (s :value)))))
(:await manager)
(assert (= :applied (get-in results [0 :status])))
(assert (= 1 (results 1)) "receipt follows synchronous descendants")
(assert (= false (get-in results [2 0])))
(assert (= :failed (get-in results [2 1 :status])))
(assert (= 1 (results 3)) "failed command does not execute its successors")
(assert (empty? (manager :_receipts)) "scope is released after failure")
(end-suite)

(start-suite :ambiguous-completion)
(def outcome @[])
(:transact manager
  (make-watch
    (producer
      (array/push outcome
        (protect
          (produce/applied
            [(make-effect (fn [_ state _] (ev/sleep 0.05) (put state :value 3)))]
            0.01))))))
(:await manager)
(assert (= :unknown (get-in outcome [0 1 :status])) "started work cannot be reported as cancelled")
(assert (= 3 (s :value)) "a late reply does not imply a mutation failed to apply")
(assert (empty? (manager :_receipts)))
(end-suite)
