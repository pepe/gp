# TODO test
(defmacro fprotect
  ```
  Similar to core library `protect`. Evaluate expressions `body`, while
  capturing any errors. Evaluates to a tuple of two elements. The first
  element is true if successful, false if an error. The second is the return
  value or the fiber that errored respectively. 
  Use it, when you want to get the stacktrace of the error.
  ```
  [& body]
  (with-syms [fib res err?]
    ~(let [,fib (,fiber/new (fn [] ,;body) :ie)
           ,res (,resume ,fib)
           ,err? (,= :error (,fiber/status ,fib))]
       [(,not ,err?) (if ,err? ,fib ,res)])))
