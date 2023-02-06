# Simple example that works through the some text files
# (see *.txt in this folder) and constructs facts based
# on the information in files.
(use /gp/events)

(def cwd
  "Construct the current directory"
  (string (os/cwd) "/examples/chains/"))

(def- shawn
  ```
  Initialize the manager with the state
  containing path to the directory file
  ```
  (make-manager
    @{:directory-file (string cwd "dir.txt")
      :users @{}}))

(defn save-user
  "Dynamic update event, that saves the user in the state."
  [user description]
  (make-update
    (fn [_ state]
      (put-in state [:users user] description))))

(defn get-user
  "Dynamic watch event that gets the user from file"
  [user]
  (make-watch
    (fn [_ state _]
      (def description (-> (string cwd user ".txt")
                           slurp string/trim))
      (save-user user description))))

(defn save-directory
  ```
  Dynamic update event that stores the directory content
  in the state
  ```
  [dir]
  (make-update
    (fn [_ state] (put state :directory dir))))

(define-watch ProcessDirectory
  ```
  Static watch event that processes the directory
  and returns the get-user event for every user in directory
  ```
  [_ state _]
  (map (fn [u] (get-user u)) (state :directory)))

(define-watch ReadDirectory
  ```
  Static watch event that reads the directory
  and returns save-directory and ProcessDirectory events
  ```
  [_ state _]
  (def dir
    (->> (state :directory-file)
         slurp string/trim
         (string/split "\n")))
  [(save-directory dir) ProcessDirectory])

# 
(define-effect PrintUsers
  ```
  Static effect event that prints the user facts as read
  from the files
  ```
  [_ state _]
  (loop [[u q] :pairs (state :users)]
    (print u " is " q)))

# transact processing event
(:transact shawn ReadDirectory)

# transact event to print the results
(:transact shawn PrintUsers)
