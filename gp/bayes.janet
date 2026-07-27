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

(defn transition?
  "Return true when `value` is a stochastic transition."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :transition (value :model))))

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
  "Return the tuple of support labels of a categorical distribution or
  stochastic transition."
  [value]
  (unless (or (categorical? value) (transition? value))
    (error "expected a categorical distribution or transition"))
  (value :support))

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

(defn top
  "Return up to `k` support labels of a categorical distribution, most
  probable first."
  [distribution k]
  (require-categorical distribution)
  (take k (sorted-by |(- (probability distribution $))
                     (support distribution))))

(defn gaussian?
  "Return true when `value` is a multivariate Gaussian."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :gaussian (value :distribution))))

(defn gaussian
  "Construct a multivariate Gaussian from `means` and row-major dense
  `covariance`, stored as a linalg vector and :sy matrix with `dtype`
  on `engine`.

  Positive definiteness is not checked at construction; the Kalman
  update discovers it through Cholesky when it matters."
  [engine dtype means covariance]
  (unless (get float-dtypes dtype)
    (errorf "gaussian dtype must be :f32 or :f64, got %v" dtype))
  (def n (length means))
  (when (zero? n) (error "gaussian needs at least one dimension"))
  (unless (= (* n n) (length covariance))
    (errorf "gaussian needs %v-by-%v covariance values" n n))
  {:gp/bayes true :distribution :gaussian
   :mean (linalg/vctr engine dtype means)
   :covariance (linalg/sy engine dtype n covariance)})

(defn- require-gaussian
  [value]
  (unless (gaussian? value) (error "expected a Gaussian distribution"))
  value)

(defn mean
  "Return the linalg mean vector of a Gaussian."
  [distribution]
  ((require-gaussian distribution) :mean))

(defn covariance
  "Return the linalg :sy covariance of a Gaussian."
  [distribution]
  ((require-gaussian distribution) :covariance))

(defn linear-dynamics?
  "Return true when `value` is a linear-Gaussian dynamics model."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :linear-dynamics (value :model))))

(defn linear-dynamics
  "Construct linear-Gaussian dynamics `x' = F x + w` with process noise
  `w ~ N(0, Q)`: row-major `matrix` F (n-by-n) and dense `noise` Q
  (n-by-n, read through :sy semantics)."
  [engine dtype n matrix noise]
  (unless (get float-dtypes dtype)
    (errorf "linear-dynamics dtype must be :f32 or :f64, got %v" dtype))
  (unless (= (* n n) (length matrix))
    (errorf "linear-dynamics needs %v-by-%v matrix values" n n))
  (unless (= (* n n) (length noise))
    (errorf "linear-dynamics needs %v-by-%v noise values" n n))
  {:gp/bayes true :model :linear-dynamics
   :matrix (linalg/ge engine dtype n n matrix)
   :noise (linalg/sy engine dtype n noise)})

(defn observation?
  "Return true when `value` is a linear-Gaussian observation model."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/bayes))
       (= :observation (value :model))))

(defn observation
  "Construct a linear-Gaussian observation `z = H x + v` with
  measurement noise `v ~ N(0, R)`: row-major `matrix` H (m-by-n from
  state dimension n to measurement dimension m) and dense `noise` R
  (m-by-m, read through :sy semantics)."
  [engine dtype m n matrix noise]
  (unless (get float-dtypes dtype)
    (errorf "observation dtype must be :f32 or :f64, got %v" dtype))
  (unless (= (* m n) (length matrix))
    (errorf "observation needs %v-by-%v matrix values" m n))
  (unless (= (* m m) (length noise))
    (errorf "observation needs %v-by-%v noise values" m m))
  {:gp/bayes true :model :observation
   :matrix (linalg/ge engine dtype m n matrix)
   :noise (linalg/sy engine dtype m noise)})

(defn- as-ge
  [matrix]
  (linalg/ge (linalg/engine matrix) (linalg/dtype matrix)
             (linalg/mrows matrix) (linalg/ncols matrix)
             (linalg/to-array matrix)))

(defn- kalman-predict
  [belief dynamics]
  (unless (linear-dynamics? dynamics)
    (error "expected linear dynamics"))
  (def motion (dynamics :matrix))
  (def mean-next (linalg/mv motion (belief :mean)))
  (def spread
    (linalg/mm (linalg/mm motion (belief :covariance))
               (linalg/trans motion)))
  (linalg/axpy! spread 1 (as-ge (dynamics :noise)))
  (gaussian (linalg/engine motion) (linalg/dtype motion)
            (linalg/to-array mean-next)
            (linalg/to-array spread)))

(defn- kalman-update
  [prior model measurement]
  (unless (observation? model)
    (error "expected an observation model"))
  (when (nil? measurement)
    (error "gaussian update takes an observation model and a measurement"))
  (def design (model :matrix))
  (def m (linalg/mrows design))
  (def n (linalg/ncols design))
  (unless (= m (length measurement))
    (errorf "observation expects %v measurement values" m))
  (unless (= n (linalg/dim (prior :mean)))
    (error "observation and state dimensions differ"))
  (def owner (linalg/engine design))
  (def dt (linalg/dtype design))
  (def expected (linalg/to-array (linalg/mv design (prior :mean))))
  (def innovation
    (seq [i :range [0 m]] (- (get measurement i) (expected i))))
  (def projected (linalg/mm design (prior :covariance)))
  (def surprise (linalg/mm projected (linalg/trans design)))
  (linalg/axpy! surprise 1 (as-ge (model :noise)))
  (def factor (linalg/cholesky surprise))
  (def factor-t (linalg/trans factor))
  (def gain-t-values (array/new-filled (* m n) 0))
  (loop [j :range [0 n]]
    (def column
      (linalg/solve factor-t
                    (linalg/solve factor (linalg/col projected j))))
    (loop [i :range [0 m]]
      (put gain-t-values (+ (* i n) j) (linalg/entry column i))))
  (def gain (linalg/trans (linalg/ge owner dt m n gain-t-values)))
  (def shift
    (linalg/to-array
      (linalg/mv gain (linalg/vctr owner dt innovation))))
  (def mean-prior (linalg/to-array (prior :mean)))
  (def spread (as-ge (prior :covariance)))
  (linalg/axpy! spread -1 (linalg/mm gain projected))
  (gaussian owner dt
            (seq [i :range [0 n]] (+ (mean-prior i) (shift i)))
            (linalg/to-array spread)))

(defn update
  "Return the posterior after weighing `prior` by evidence.

  For a categorical prior, `evidence` is one non-negative likelihood
  per support label; the pointwise product runs on the host (an
  elementwise vector product is recorded linalg client pressure) and
  zero total posterior mass — an observation impossible under every
  label — is an error.

  For a Gaussian prior, `evidence` is a linear-Gaussian observation
  model and `measurement` its observed values; the Kalman measurement
  update runs through Cholesky and triangular solves, so a degenerate
  innovation covariance is an error."
  [prior evidence &opt measurement]
  (if (gaussian? prior)
    (kalman-update prior evidence measurement)
    (do
      (unless (nil? measurement)
        (error "categorical update takes likelihoods only"))
      (require-categorical prior)
      (def labels (prior :support))
      (unless (= (length labels) (length evidence))
        (errorf "update needs %v likelihoods for %v labels"
                (length labels) (length labels)))
      (def priors (prior :probabilities))
      (def weights
        (seq [position :range [0 (length labels)]]
          (* (linalg/entry priors position) (get evidence position))))
      (when (<= (reduce + 0 weights) 0)
        (error "observation has zero probability under the prior"))
      (categorical (linalg/engine priors) (linalg/dtype priors)
                   labels weights))))

(defn transition
  "Construct a stochastic transition over `support` from row-major
  non-negative `rows`, one conditional weight row per source label.

  Rows normalize at construction into P(destination | source), stored
  as a linalg matrix with `dtype` on `engine`. A source row with zero
  total mass is an error."
  [engine dtype support rows]
  (unless (get float-dtypes dtype)
    (errorf "transition dtype must be :f32 or :f64, got %v" dtype))
  (def labels (tuple ;support))
  (when (empty? labels) (error "transition support must not be empty"))
  (unless (= (* (length labels) (length labels)) (length rows))
    (errorf "transition needs %v-by-%v conditional weights"
            (length labels) (length labels)))
  (def normalized @[])
  (loop [source :range [0 (length labels)]]
    (def start (* source (length labels)))
    (def row (seq [position :range [start (+ start (length labels))]]
               (get rows position)))
    (array/concat normalized (normalized-weights row "transition")))
  {:gp/bayes true :model :transition
   :support labels
   :index (label-index labels "support")
   :matrix (linalg/ge engine dtype (length labels) (length labels) normalized)})

(defn predict
  "Return the belief after one step of `dynamics`: the motion half of a
  Bayes filter, with `update` as the evidence half. A filter step is
  their composition, `(update (predict belief dynamics) evidence)`.

  A categorical belief steps through a stochastic transition — the
  matrix transposed and multiplied against the belief vector through
  linalg. A Gaussian belief steps through linear dynamics — the Kalman
  prediction `mean' = F mean`, `P' = F P Fᵀ + Q`. Either way the result
  is a fresh distribution on the engine of `dynamics`."
  [belief dynamics]
  (if (gaussian? belief)
    (kalman-predict belief dynamics)
    (do
      (require-categorical belief)
      (unless (transition? dynamics)
        (error "expected a stochastic transition"))
      (unless (= (belief :support) (dynamics :support))
        (error "predict requires matching support labels"))
      (categorical
        (linalg/engine (dynamics :matrix))
        (linalg/dtype (dynamics :matrix))
        (belief :support)
        (linalg/to-array
          (linalg/mv (linalg/trans (dynamics :matrix))
                     (belief :probabilities)))))))

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
