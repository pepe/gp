# Predict the next word of a TWM todo from time and history, as a
# real-data client of gp/bayes. Expects a path to an export of done
# todos: a Janet table of id -> {:created ... :text ...}.
#
#   janet examples/todo-prediction.janet path/to/bayes.jdn

(import gp/compute/cpp)
(import gp/linalg)
(import gp/bayes)

(def path (get (dyn :args) 1))
(unless path
  (print "usage: janet examples/todo-prediction.janet path/to/bayes.jdn")
  (os/exit 1))

(def host (cpp/engine))
(def alpha 1)

(def todos (sorted-by |($ :created) (values (parse (slurp path)))))
(def split (math/floor (* 0.8 (length todos))))
(def train (take split todos))
(def test (drop split todos))
(printf "todos: %d train / %d held out (last %.0f days)"
        (length train) (length test)
        (/ (- ((last todos) :created) ((first test) :created)) 86400))

(defn tokens [todo] (string/split " " (todo :text)))
(defn tag [todo] (first (tokens todo)))

(defn hour-bucket [ts]
  (def hour ((os/date ts true) :hours))
  (cond
    (< hour 7) :early
    (< hour 10) :morning
    (< hour 12) :late-morning
    (< hour 14) :midday
    (< hour 18) :afternoon
    :evening))

(defn weekday [ts] ((os/date ts true) :week-day))

# Evidence decays with a half-life so the model tracks the current
# regime instead of averaging four months — counting as forgetting,
# the first step toward the temporal filter framing.
(def half-life-days 14)
(def train-end ((last train) :created))
(defn recency [todo]
  (math/exp (* (/ (- (todo :created) train-end) 86400)
               (/ (math/log 2) half-life-days))))

# Context features per todo: creation-time buckets and the previous
# todo's tag, :none when there is none or the tag is unknown to training.
(def train-tags (distinct (map tag train)))
(def known-tag (tabseq [t :in train-tags] t t))
# Tag model: naive Bayes with class = tag, add-alpha smoothed counts.
(def hour-support [:early :morning :late-morning :midday :afternoon :evening])
(def weekday-support [0 1 2 3 4 5 6])
(def previous-support (tuple :none ;train-tags))

(def feature-definitions
  {:hour-bucket
   {:support hour-support
    :pick (fn [todo _] (hour-bucket (todo :created)))}
   :weekday
   {:support weekday-support
    :pick (fn [todo _] (weekday (todo :created)))}
   :previous-tag
   {:support previous-support
    :pick (fn [_ previous] (get known-tag (if previous (tag previous)) :none))}})

# Measured on 132 held-out todos (top-1/top-3 tag hit rates):
#   hour+weekday+previous 27/61, hour+previous 27/64, hour 29/65,
#   previous 24/67, static most-frequent baseline 15/68.
# Features are correlated, so each addition raises top-1 confidence and
# erodes top-3 coverage — naive Bayes over-confidence measured live.
(def active-features [:hour-bucket :previous-tag])

(defn features [todo previous]
  (tabseq [key :in active-features]
    key (((feature-definitions key) :pick) todo previous)))

(defn feature-rows [support pick]
  (def index (tabseq [[position value] :pairs support] value position))
  (def rows (seq [_ :range [0 (* (length train-tags) (length support))]] alpha))
  (eachp [position todo] train
    (def class (index-of (tag todo) train-tags))
    (def value (pick todo (get train (- position 1))))
    (def column (get index value))
    (def cell (+ (* class (length support)) column))
    (put rows cell (+ (recency todo) (rows cell))))
  rows)

(def tag-counts @{})
(each todo train
  (put tag-counts (tag todo) (+ (recency todo) (get tag-counts (tag todo) 0))))
(def tag-model
  (bayes/naive-bayes
    (bayes/categorical host :f64 train-tags
                       (map |(tag-counts $) train-tags))
    (tabseq [key :in active-features]
      key (let [definition (feature-definitions key)]
            {:support (definition :support)
             :rows (feature-rows (definition :support)
                                 (definition :pick))}))))

# Word model: one categorical per context word over its observed
# successors, the tag serving as the first context. On a context unseen
# in training, back off to the tag's bag of words. A word unseen either
# way scores as a miss.
(def successor-counts @{})
(def tag-word-counts @{})
(each todo train
  (def words (tokens todo))
  (def bag (or (get tag-word-counts (tag todo))
               (let [fresh @{}] (put tag-word-counts (tag todo) fresh) fresh)))
  (loop [position :range [1 (length words)]]
    (def context (words (- position 1)))
    (def counts (or (get successor-counts context)
                    (let [fresh @{}] (put successor-counts context fresh) fresh)))
    (put counts (words position)
         (+ (recency todo) (get counts (words position) 0)))
    (put bag (words position)
         (+ (recency todo) (get bag (words position) 0)))))
(defn counts-categorical [counts]
  (bayes/categorical host :f64 (keys counts) (values counts)))
(def word-model
  (tabseq [[context counts] :pairs successor-counts
           :when (not (empty? counts))]
    context (counts-categorical counts)))
(def tag-word-model
  (tabseq [[context counts] :pairs tag-word-counts
           :when (not (empty? counts))]
    context (counts-categorical counts)))

# Whole-todo completion: known full texts ranked within their tag.
(def text-counts-by-tag @{})
(each todo train
  (def counts (or (get text-counts-by-tag (tag todo))
                  (let [fresh @{}] (put text-counts-by-tag (tag todo) fresh) fresh)))
  (put counts (todo :text) (+ (recency todo) (get counts (todo :text) 0))))
(def text-model
  (tabseq [[context counts] :pairs text-counts-by-tag]
    context (counts-categorical counts)))

(defn top [distribution k]
  (take k (sorted-by |(- (bayes/probability distribution $))
                     (bayes/support distribution))))

# Evaluation: top-1 and top-3 hit rates on the held-out tail, against
# static most-frequent baselines.
(def frequent-tags (sorted-by |(- (tag-counts $)) train-tags))
(var tag-top1 0)
(var tag-top3 0)
(var tag-baseline1 0)
(var tag-baseline3 0)
(eachp [position todo] test
  (def previous (if (= position 0) (last train) (test (- position 1))))
  (def predicted (top (bayes/posterior tag-model (features todo previous)) 3))
  (when (= (tag todo) (first predicted)) (++ tag-top1))
  (when (index-of (tag todo) predicted) (++ tag-top3))
  (when (= (tag todo) (first frequent-tags)) (++ tag-baseline1))
  (when (index-of (tag todo) (take 3 frequent-tags)) (++ tag-baseline3)))
(printf "tag prediction:   top-1 %2.0f%%   top-3 %2.0f%%   (static baseline %2.0f%% / %2.0f%%)"
        (* 100 (/ tag-top1 (length test)))
        (* 100 (/ tag-top3 (length test)))
        (* 100 (/ tag-baseline1 (length test)))
        (* 100 (/ tag-baseline3 (length test))))

(var word-total 0)
(var word-top1 0)
(var word-top3 0)
(var word-missing 0)
(each todo test
  (def words (tokens todo))
  (loop [position :range [1 (length words)]]
    (++ word-total)
    (def distribution
      (or (get word-model (words (- position 1)))
          (get tag-word-model (first words))))
    (if distribution
      (do
        (def predicted (top distribution 3))
        (when (= (words position) (first predicted)) (++ word-top1))
        (when (index-of (words position) predicted) (++ word-top3)))
      (++ word-missing))))
(printf "next word:        top-1 %2.0f%%   top-3 %2.0f%%   (%d predictions, %.0f%% without any model)"
        (* 100 (/ word-top1 word-total))
        (* 100 (/ word-top3 word-total))
        word-total
        (* 100 (/ word-missing word-total)))

(var text-repeats 0)
(var text-top3 0)
(each todo test
  (def known (get text-model (tag todo)))
  (def seen (and known (index-of (todo :text) (bayes/support known))))
  (when seen (++ text-repeats))
  (when (and known (index-of (todo :text) (top known 3)))
    (++ text-top3)))
(printf "whole todo:       top-3 %2.0f%%   (%.0f%% of held-out todos repeat a training text)"
        (* 100 (/ text-top3 (length test)))
        (* 100 (/ text-repeats (length test))))

# Demonstration: a Tuesday morning with the previous todo under $mtb.
(def demo-posterior
  (bayes/posterior tag-model
                   (tabseq [key :in active-features]
                     key (get {:hour-bucket :morning :weekday 2
                               :previous-tag "$mtb"}
                              key))))
(print "\nTuesday morning, previous todo $mtb:")
(each candidate (top demo-posterior 3)
  (printf "  %-6s %4.1f%%" candidate
          (* 100 (bayes/probability demo-posterior candidate))))
(each context ["$pp" "$mtb" "$twm"]
  (when-let [distribution (get word-model context)]
    (printf "after %s: %s" context (string/join (top distribution 3) ", "))))
