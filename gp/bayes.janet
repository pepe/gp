(import gp/compute)
(import gp/linalg)

# bayes-0 phase 1: categorical updating and naive Bayes over linalg-0
# values. All probability arithmetic is host-side; every log/exp call
# site here is evidence for the kernel-0.1 review gate, and elementwise
# products are recorded linalg pressure. See docs/bayes.md.

(def- float-dtypes {:f32 true :f64 true})

(defn categorical?
  "Return true when `value` is a categorical distribution."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :categorical (value :distribution))))

(defn- require-categorical
  [value]
  (unless (categorical? value) (error "expected a categorical distribution"))
  value)

(defn- label-index
  [labels what]
  (def index @{})
  (eachp [position stored] labels
    (when (get index stored)
      (errorf "duplicate %s label %v" what stored))
    (put index stored position))
  (freeze index))

(defn- normalized-weights
  [weights what]
  (each weight weights
    (when (< weight 0)
      (errorf "%s weights must be non-negative" what)))
  (def total (reduce + 0 weights))
  (when (<= total 0)
    (errorf "%s weights must have positive total mass" what))
  (map |(/ $ total) weights))

(defn categorical
  "Construct a categorical distribution over `support` from non-negative
  `weights`, normalized at construction.

  Probabilities are stored as a linalg vector with `dtype` (:f32 or
  :f64) on `engine`. Support labels must be distinct and weights must
  carry positive total mass."
  [engine dtype support weights]
  (unless (get float-dtypes dtype)
    (errorf "categorical dtype must be :f32 or :f64, got %v" dtype))
  (def labels (tuple ;support))
  (when (empty? labels) (error "categorical support must not be empty"))
  (unless (= (length labels) (length weights))
    (errorf "categorical needs %v weights for %v labels"
            (length labels) (length labels)))
  {:gp/bayes true :distribution :categorical
   :support labels
   :index (label-index labels "support")
   :probabilities
   (linalg/vctr engine dtype (normalized-weights weights "categorical"))})

(defn support
  "Return the tuple of support labels of a categorical distribution."
  [distribution]
  ((require-categorical distribution) :support))

(defn probabilities
  "Return the linalg probability vector of a categorical distribution."
  [distribution]
  ((require-categorical distribution) :probabilities))

(defn probability
  "Return the probability of `outcome` as a host number."
  [distribution outcome]
  (require-categorical distribution)
  (def position (get (distribution :index) outcome))
  (unless position
    (errorf "unknown support label %v" outcome))
  (linalg/entry (distribution :probabilities) position))

(defn update
  "Return the posterior categorical after weighing `prior` by
  `likelihoods`, one non-negative host number per support label.

  The pointwise product runs on the host; an elementwise vector product
  is recorded linalg client pressure. Zero total posterior mass — an
  observation impossible under every label — is an error."
  [prior likelihoods]
  (require-categorical prior)
  (def labels (prior :support))
  (unless (= (length labels) (length likelihoods))
    (errorf "update needs %v likelihoods for %v labels"
            (length labels) (length labels)))
  (def priors (prior :probabilities))
  (def weights
    (seq [position :range [0 (length labels)]]
      (* (linalg/entry priors position) (get likelihoods position))))
  (when (<= (reduce + 0 weights) 0)
    (error "observation has zero probability under the prior"))
  (categorical (linalg/engine priors) (linalg/dtype priors) labels weights))

(defn naive-bayes?
  "Return true when `value` is a naive Bayes model."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :naive-bayes (value :model))))

(defn- require-naive-bayes
  [value]
  (unless (naive-bayes? value) (error "expected a naive Bayes model"))
  value)

(defn naive-bayes
  "Construct a naive Bayes model from a categorical `classes` prior and
  a dictionary of `features`.

  Each feature maps a key to `{:support [...] :rows [...]}` where rows
  hold one row-major conditional weight row per class. Rows normalize at
  construction into per-class conditional distributions stored as a
  linalg matrix on the engine of `classes`."
  [classes features]
  (require-categorical classes)
  (def class-count (length (classes :support)))
  (def owner (linalg/engine (classes :probabilities)))
  (def dtype (linalg/dtype (classes :probabilities)))
  (def prepared @{})
  (eachp [key feature] features
    (def labels (tuple ;(get feature :support [])))
    (when (empty? labels)
      (errorf "feature %v must have a non-empty support" key))
    (def rows (get feature :rows []))
    (unless (= (* class-count (length labels)) (length rows))
      (errorf "feature %v needs %v-by-%v conditional weights"
              key class-count (length labels)))
    (def normalized @[])
    (loop [class :range [0 class-count]]
      (def start (* class (length labels)))
      (def row (seq [position :range [start (+ start (length labels))]]
                 (get rows position)))
      (array/concat normalized
        (normalized-weights row (string "feature " key))))
    (put prepared key
         {:support labels
          :index (label-index labels (string "feature " key))
          :likelihoods
          (linalg/ge owner dtype class-count (length labels) normalized)}))
  {:gp/bayes true :model :naive-bayes
   :classes classes
   :features (freeze prepared)})

(defn classes
  "Return the categorical class prior of a naive Bayes model."
  [model]
  ((require-naive-bayes model) :classes))

(defn posterior
  "Return the posterior categorical over classes given `observations`,
  a dictionary from feature key to observed value label.

  Unobserved features are simply absent. Evidence accumulates in log
  space with log-sum-exp normalization, so long products of small
  likelihoods do not underflow. Observations impossible under every
  class are an error."
  [model observations]
  (require-naive-bayes model)
  (def prior (model :classes))
  (def class-count (length (prior :support)))
  (def log-weights
    (seq [class :range [0 class-count]]
      (math/log (linalg/entry (prior :probabilities) class))))
  (eachp [key value] observations
    (def feature (get (model :features) key))
    (unless feature (errorf "unknown feature %v" key))
    (def column (get (feature :index) value))
    (unless column
      (errorf "unknown value %v for feature %v" value key))
    (loop [class :range [0 class-count]]
      (put log-weights class
           (+ (log-weights class)
              (math/log
                (linalg/entry (feature :likelihoods) class column))))))
  (def peak (max ;log-weights))
  (when (= peak math/-inf)
    (error "observations have zero probability under every class"))
  (categorical (linalg/engine (prior :probabilities))
               (linalg/dtype (prior :probabilities))
               (prior :support)
               (map |(math/exp (- $ peak)) log-weights)))
