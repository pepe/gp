# Simple example that works through the some text files
# (see *.txt in this folder) and constructs facts based
# on the information in files.
(use /gp/events)

# Get the current directory
(def cwd (string (os/cwd) "/examples/chains/"))

# Initialize the shawn with the envelope
# containing path to the directory file
(def- shawn
  (make-manager
    @{:directory-file (string cwd "dir.txt")
      :users @{}}))

# Dynamic UpdateAct, that saves the user in the envelope.
(defn save-user [user description]
  (make-update
    (fn [_ state]
      (put-in state [:users user] description))))

# Dynamic WatchAct that gets the user from file
(defn get-user [user]
  (make-watch
    (fn [_ state _]
      (def description (-> (string cwd user ".txt")
                           slurp string/trim))
      (save-user user description))))

# Dynamic UpdateAct that stores the directory content
# in the envelope
(defn save-directory [dir]
  (make-update
    (fn [_ state] (put state :directory dir))))

# Static WatchAct that processes the directory
# and returns the get-user Act for every user in directory
(define-watch ProcessDirectory [_ state _]
  (map (fn [u] (get-user u)) (state :directory)))

# Static WatchAct that reads the directory
# and returns save-directory and ProcessDirectory Acts
(define-watch ReadDirectory [_ state _]
  (def dir
    (->> (state :directory-file)
         slurp string/trim
         (string/split "\n")))
  [(save-directory dir) ProcessDirectory])

# Static EffectAct that prints the user facts as read
# from the files
(define-effect PrintUsers [_ state _]
  (loop [[u q] :pairs (state :users)]
    (print u " is " q)))

# Confirm ReadDirectory Act
(:transact shawn ReadDirectory)

# Confirm PrintUsers Act to print the results
(:transact shawn PrintUsers)
