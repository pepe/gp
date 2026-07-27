# A discrete Bayes filter over TWM todo tags: Markov dynamics counted
# from consecutive todos, creation-hour emission as evidence, evaluated
# on the same temporal split as examples/todo-prediction.janet.
#
#   janet examples/todo-filter.janet path/to/bayes.jdn

(import gp/compute/cpp)
(import gp/bayes)

(def path (get (dyn :args) 1))
(unless path
  (print "usage: janet examples/todo-filter.janet path/to/bayes.jdn")
  (os/exit 1))

(def host (cpp/engine))
(def alpha 1)

(def todos (sorted-by |($ :created) (values (parse (slurp path)))))
(def split (math/floor (* 0.8 (length todos))))
(def train (take split todos))
(def test (drop split todos))

(defn tag [todo] (first (string/split " " (todo :text))))

(def hour-support [:early :morning :late-morning :midday :afternoon :evening])
(defn hour-bucket [ts]
  (def hour ((os/date ts true) :hours))
  (cond
    (< hour 7) :early
    (< hour 10) :morning
    (< hour 12) :late-morning
    (< hour 14) :midday
    (< hour 18) :afternoon
    :evening))

(def half-life-days 14)
(def train-end ((last train) :created))
(defn recency [todo]
  (math/exp (* (/ (- (todo :created) train-end) 86400)
               (/ (math/log 2) half-life-days))))

(def tags (distinct (map tag train)))
(def tag-index (tabseq [[position value] :pairs tags] value position))
(def n (length tags))

# Dynamics: recency-weighted counts of consecutive tag pairs. The
# smoothing mass is spread across n destinations per row, so it stays
# a small fraction of the observed pairs instead of swamping them.
(def dynamics-alpha (/ alpha n))
(def dynamics-rows (seq [_ :range [0 (* n n)]] dynamics-alpha))
(loop [position :range [1 (length train)]]
  (def source (tag-index (tag (train (- position 1)))))
  (def destination (tag-index (tag (train position))))
  (def cell (+ (* source n) destination))
  (put dynamics-rows cell
       (+ (recency (train position)) (dynamics-rows cell))))
(def dynamics (bayes/transition host :f64 tags dynamics-rows))

# Emission: recency-weighted counts of creation-hour buckets per tag,
# read column-wise as P(observed bucket | tag) evidence.
(def bucket-index (tabseq [[position value] :pairs hour-support] value position))
(def emission-counts (seq [_ :range [0 (* n (length hour-support))]] alpha))
(each todo train
  (def cell (+ (* (tag-index (tag todo)) (length hour-support))
               (bucket-index (hour-bucket (todo :created)))))
  (put emission-counts cell (+ (recency todo) (emission-counts cell))))
(def emission-totals
  (seq [class :range [0 n]]
    (reduce + 0 (seq [bucket :range [0 (length hour-support)]]
                  (emission-counts (+ (* class (length hour-support)) bucket))))))
(defn evidence [bucket]
  (def column (bucket-index bucket))
  (seq [class :range [0 n]]
    (/ (emission-counts (+ (* class (length hour-support)) column))
       (emission-totals class))))

(defn one-hot [known-tag]
  (seq [position :range [0 n]] (if (= position (tag-index known-tag)) 1 0)))

# Filter loop: predict with the dynamics, weigh by the hour evidence,
# score, then condition on the observed tag before the next step.
(def frequent
  (do
    (def weighted @{})
    (each todo train
      (put weighted (tag todo) (+ (recency todo) (get weighted (tag todo) 0))))
    (sorted-by |(- (weighted $)) tags)))
(var belief (bayes/categorical host :f64 tags (one-hot (tag (last train)))))
(var top1 0)
(var top3 0)
(var baseline1 0)
(var baseline3 0)
(each todo test
  (def prior (bayes/predict belief dynamics))
  (def posterior (bayes/update prior (evidence (hour-bucket (todo :created)))))
  (def predicted (bayes/top posterior 3))
  (when (= (tag todo) (first predicted)) (++ top1))
  (when (index-of (tag todo) predicted) (++ top3))
  (when (= (tag todo) (first frequent)) (++ baseline1))
  (when (index-of (tag todo) (take 3 frequent)) (++ baseline3))
  (set belief
       (if (get tag-index (tag todo))
         (bayes/update posterior (one-hot (tag todo)))
         posterior)))
(printf "filter (dynamics + hour evidence) on %d held-out todos:" (length test))
(printf "  top-1 %2.0f%%   top-3 %2.0f%%   (static baseline %2.0f%% / %2.0f%%)"
        (* 100 (/ top1 (length test)))
        (* 100 (/ top3 (length test)))
        (* 100 (/ baseline1 (length test)))
        (* 100 (/ baseline3 (length test))))

(def demo
  (bayes/update (bayes/predict
                  (bayes/categorical host :f64 tags (one-hot "$mtb"))
                  dynamics)
                (evidence :morning)))
(print "\nmorning, previous todo $mtb:")
(each candidate (bayes/top demo 3)
  (printf "  %-6s %4.1f%%" candidate (* 100 (bayes/probability demo candidate))))
