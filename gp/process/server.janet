(defn start
  ```
  This function starts server. Usually in the fiber.
  
  It takes channel to which it will put incomming connection under tag `:conn`.

  It takes two optional arguments:
  - `host` on which server starts. Default `localhost`
  - `port` on which server starts. Default `8888`
  ```
  [chan host port]

  (default host "localhost")
  (default port "8888")

  (ev/go
    (fiber/new
      (fn accept-connection [server]
        (forever (ev/give-supervisor :conn (net/accept server)))))
    (net/listen host port) chan))
