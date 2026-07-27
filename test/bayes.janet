(use spork/test jhydro)
(import gp/compute)
(import gp/compute/cpp)
(import gp/compute/opencl)
(import gp/linalg)
(import gp/bayes)

(start-suite "Bayes documentation")
(assert-docs "gp/bayes")
(end-suite)

(def host (cpp/engine))

(defn approx=
  [expected actual &opt tolerance]
  (default tolerance 1e-9)
  (< (math/abs (- expected actual)) tolerance))

(start-suite "Bayes categorical")

(def weather (bayes/categorical host :f64 [:sunny :rainy :cloudy] [2 3 5]))
(assert (bayes/categorical? weather) "categorical value")
(assert (not (bayes/categorical? {:distribution :categorical}))
        "foreign struct rejected")
(assert (= [:sunny :rainy :cloudy] (bayes/support weather)) "support labels")
(assert (linalg/vector? (bayes/probabilities weather))
        "probabilities are a linalg vector")
(assert (= :f64 (linalg/dtype (bayes/probabilities weather)))
        "probability dtype")
(assert (approx= 0.2 (bayes/probability weather :sunny)) "normalized weight")
(assert (approx= 0.5 (bayes/probability weather :cloudy)) "normalized weight")
(assert (approx= 1 (linalg/sum (bayes/probabilities weather)))
        "probabilities sum to one")

(assert-error "unknown label" (bayes/probability weather :snowy))
(assert-error "weight count must match"
              (bayes/categorical host :f64 [:a :b] [1]))
(assert-error "negative weights rejected"
              (bayes/categorical host :f64 [:a :b] [1 -1]))
(assert-error "zero mass rejected" (bayes/categorical host :f64 [:a :b] [0 0]))
(assert-error "duplicate labels rejected"
              (bayes/categorical host :f64 [:a :a] [1 1]))
(assert-error "empty support rejected" (bayes/categorical host :f64 [] []))
(assert-error "integer dtype rejected"
              (bayes/categorical host :i32 [:a :b] [1 1]))

(def updated (bayes/update weather [0.9 0.3 0.1]))
(assert (= [:sunny :rainy :cloudy] (bayes/support updated))
        "update preserves support")
# weights: [0.2*0.9 0.3*0.3 0.5*0.1] = [0.18 0.09 0.05], total 0.32
(assert (approx= (/ 0.18 0.32) (bayes/probability updated :sunny))
        "posterior mass")
(assert (approx= (/ 0.05 0.32) (bayes/probability updated :cloudy))
        "posterior mass")

(def chained (bayes/update (bayes/update weather [0.9 0.3 0.1]) [0.5 0.5 0.9]))
(def joint (bayes/update weather [0.45 0.15 0.09]))
(assert (approx= (bayes/probability joint :sunny)
                 (bayes/probability chained :sunny))
        "sequential updates compose")
(assert (approx= (bayes/probability joint :cloudy)
                 (bayes/probability chained :cloudy))
        "sequential updates compose")

(assert-error "impossible observation rejected"
              (bayes/update weather [0 0 0]))
(assert-error "likelihood count must match" (bayes/update weather [1 1]))

(end-suite)

(start-suite "Bayes naive Bayes")

(def spam-model
  (bayes/naive-bayes
    (bayes/categorical host :f64 [:spam :ham] [1 3])
    {:offer {:support [:yes :no]
             :rows [8 2
                    1 9]}
     :greeting {:support [:generic :personal]
                :rows [7 3
                       2 8]}}))
(assert (bayes/naive-bayes? spam-model) "naive Bayes value")
(assert (= [:spam :ham] (bayes/support (bayes/classes spam-model)))
        "class labels")

(def empty-posterior (bayes/posterior spam-model {}))
(assert (approx= 0.25 (bayes/probability empty-posterior :spam))
        "no observations returns the prior")

# P(spam|offer=yes) = 0.25*0.8 / (0.25*0.8 + 0.75*0.1) = 0.2/0.275
(def one-feature (bayes/posterior spam-model {:offer :yes}))
(assert (approx= (/ 0.2 0.275) (bayes/probability one-feature :spam))
        "single-feature posterior")

# spam: 0.25*0.8*0.7 = 0.14; ham: 0.75*0.1*0.2 = 0.015; total 0.155
(def two-features (bayes/posterior spam-model {:offer :yes :greeting :generic}))
(assert (approx= (/ 0.14 0.155) (bayes/probability two-features :spam))
        "two-feature posterior")
(assert (approx= 1 (linalg/sum (bayes/probabilities two-features)))
        "posterior sums to one")

(assert-error "unknown feature" (bayes/posterior spam-model {:subject :yes}))
(assert-error "unknown feature value" (bayes/posterior spam-model {:offer :maybe}))
(assert-error "feature shape must match class count"
              (bayes/naive-bayes (bayes/classes spam-model)
                                 {:broken {:support [:x] :rows [1 2 3]}}))
(assert-error "zero-mass conditional row rejected"
              (bayes/naive-bayes (bayes/classes spam-model)
                                 {:broken {:support [:x :y] :rows [1 1 0 0]}}))

(assert-error "impossible under every class"
              (bayes/posterior
                (bayes/naive-bayes
                  (bayes/categorical host :f64 [:a :b] [1 1])
                  {:only {:support [:x :y] :rows [1 0 1 0]}})
                {:only :y}))

(def underflow-model
  (bayes/naive-bayes
    (bayes/categorical host :f64 [:a :b] [1 1])
    {:evidence {:support [:rare :common]
                :rows [1e-200 1
                       2e-200 1]}}))
# direct products would underflow to zero; log space keeps the ratio 1:2
(def underflow-posterior (bayes/posterior underflow-model {:evidence :rare}))
(assert (approx= (/ 1 3) (bayes/probability underflow-posterior :a))
        "log-space evidence survives underflow")

(end-suite)

(start-suite "Bayes discrete filter")

(assert (deep= [:cloudy :rainy] (tuple ;(bayes/top weather 2))) "top-k ordering")
(assert (= 3 (length (bayes/top weather 10))) "top-k bounded by support")
(assert-error "top rejects other values" (bayes/top spam-model 3))

(def identity-dynamics
  (bayes/transition host :f64 [:sunny :rainy :cloudy]
                    [1 0 0
                     0 1 0
                     0 0 1]))
(assert (bayes/transition? identity-dynamics) "transition value")
(assert (= [:sunny :rainy :cloudy] (bayes/support identity-dynamics))
        "transition support")
(def stationary (bayes/predict weather identity-dynamics))
(assert (approx= 0.3 (bayes/probability stationary :rainy))
        "identity dynamics preserve belief")
(assert (approx= 0.5 (bayes/probability stationary :cloudy))
        "identity dynamics preserve belief")

(def rotation
  (bayes/transition host :f64 [:sunny :rainy :cloudy]
                    [0 1 0
                     0 0 1
                     1 0 0]))
(def rotated (bayes/predict weather rotation))
(assert (approx= 0.5 (bayes/probability rotated :sunny))
        "permutation dynamics permute belief")
(assert (approx= 0.2 (bayes/probability rotated :rainy))
        "permutation dynamics permute belief")

(def mixing
  (bayes/transition host :f64 [:sunny :rainy :cloudy]
                    [1 1 1
                     1 1 1
                     1 1 1]))
(def mixed (bayes/predict weather mixing))
(assert (approx= (/ 1 3) (bayes/probability mixed :sunny))
        "uniform dynamics erase information")

(assert-error "transition rows must be square"
              (bayes/transition host :f64 [:a :b] [1 0 0 1 0 0]))
(assert-error "zero-mass transition row rejected"
              (bayes/transition host :f64 [:a :b] [1 1 0 0]))
(assert-error "transition needs a float dtype"
              (bayes/transition host :i32 [:a :b] [1 0 0 1]))
(assert-error "predict requires matching supports"
              (bayes/predict weather (bayes/transition host :f64 [:a :b] [1 0 0 1])))
(assert-error "predict requires a transition" (bayes/predict weather weather))

# Russell-Norvig umbrella world: P(rain stays) 0.7, P(umbrella|rain)
# 0.9, P(umbrella|dry) 0.2, uniform start, umbrella seen twice.
(def umbrella-dynamics
  (bayes/transition host :f64 [:rain :dry] [0.7 0.3 0.3 0.7]))
(def umbrella-evidence [0.9 0.2])
(def day0 (bayes/categorical host :f64 [:rain :dry] [1 1]))
(def day1 (bayes/update (bayes/predict day0 umbrella-dynamics) umbrella-evidence))
(assert (approx= (/ 9 11) (bayes/probability day1 :rain))
        "umbrella day one matches the textbook posterior")
(def day2 (bayes/update (bayes/predict day1 umbrella-dynamics) umbrella-evidence))
(assert (approx= (/ 621 703) (bayes/probability day2 :rain))
        "umbrella day two matches the textbook posterior")

(end-suite)

(start-suite "Bayes Kalman filter")

(def state0 (bayes/gaussian host :f64 [0] [1]))
(assert (bayes/gaussian? state0) "gaussian value")
(assert (deep= @[0] (linalg/to-array (bayes/mean state0))) "gaussian mean")
(assert (= :sy (linalg/structure (bayes/covariance state0)))
        "gaussian covariance structure")

(def position-sensor (bayes/observation host :f64 1 1 [1] [1]))
(def state1 (bayes/update state0 position-sensor [1]))
(assert (approx= 0.5 (linalg/entry (bayes/mean state1) 0))
        "scalar Kalman update mean")
(assert (approx= 0.5 (linalg/entry (bayes/covariance state1) 0 0))
        "scalar Kalman update variance")

(def drift (bayes/linear-dynamics host :f64 1 [1] [0.25]))
(def state1-predicted (bayes/predict state1 drift))
(assert (approx= 0.5 (linalg/entry (bayes/mean state1-predicted) 0))
        "scalar Kalman prediction mean")
(assert (approx= 0.75 (linalg/entry (bayes/covariance state1-predicted) 0 0))
        "scalar Kalman prediction variance grows by the process noise")

(def state2 (bayes/update state1-predicted position-sensor [2]))
(assert (approx= (/ 8 7) (linalg/entry (bayes/mean state2) 0))
        "scalar Kalman second update matches exact fractions")
(assert (approx= (/ 3 7) (linalg/entry (bayes/covariance state2) 0 0))
        "scalar Kalman second variance matches exact fractions")

(def plane (bayes/gaussian host :f64 [1 0] [1 0 0 1]))
(def rotate (bayes/linear-dynamics host :f64 2 [0 -1 1 0] [0 0 0 0]))
(def rotated-state (bayes/predict plane rotate))
(assert (approx= 0 (linalg/entry (bayes/mean rotated-state) 0))
        "rotation dynamics rotate the mean")
(assert (approx= 1 (linalg/entry (bayes/mean rotated-state) 1))
        "rotation dynamics rotate the mean")
(assert (approx= 1 (linalg/entry (bayes/covariance rotated-state) 0 0))
        "rotation preserves an isotropic covariance")

(def sharp-sensor
  (bayes/observation host :f64 2 2 [1 0 0 1] [1e-6 0 0 1e-6]))
(def pinned (bayes/update plane sharp-sensor [5 7]))
(assert (approx= 5 (linalg/entry (bayes/mean pinned) 0) 1e-3)
        "sharp evidence pins the mean")
(assert (approx= 7 (linalg/entry (bayes/mean pinned) 1) 1e-3)
        "sharp evidence pins the mean")
(assert (< (linalg/entry (bayes/covariance pinned) 0 0) 1e-5)
        "sharp evidence collapses the variance")
(assert (= :tr (linalg/structure (linalg/cholesky (bayes/covariance pinned))))
        "the posterior covariance stays positive definite")

(assert-error "gaussian update needs a measurement"
              (bayes/update state0 position-sensor))
(assert-error "measurement length must match"
              (bayes/update plane sharp-sensor [1]))
(assert-error "state dimensions must match"
              (bayes/update state0 sharp-sensor [1 2]))
(assert-error "categorical update takes likelihoods only"
              (bayes/update weather [1 1 1] [1]))
(assert-error "gaussian predict needs linear dynamics"
              (bayes/predict state0 identity-dynamics))
(assert-error "categorical predict needs a transition"
              (bayes/predict weather drift))
(assert-error "gaussian covariance size must match"
              (bayes/gaussian host :f64 [1 2] [1 0 0]))
(assert-error "gaussian rejects integer dtype"
              (bayes/gaussian host :i32 [1] [1]))

(end-suite)

(start-suite "Bayes on OpenCL storage")

(when (opencl/available?)
  (def gpu (opencl/engine))
  (def device-prior (bayes/categorical gpu :f32 [:up :down] [1 1]))
  (assert (= "opencl" (compute/engine-name
                        (linalg/engine (bayes/probabilities device-prior))))
          "device-resident distribution")
  (def device-posterior (bayes/update device-prior [0.7 0.1]))
  (assert (approx= 0.875 (bayes/probability device-posterior :up) 1e-6)
          "device categorical update")
  (assert (approx= 1 (linalg/sum (bayes/probabilities device-posterior)) 1e-6)
          "device posterior sums to one through the kernel-0 reduction")
  (def device-dynamics
    (bayes/transition gpu :f32 [:up :down] [0.9 0.1 0.4 0.6]))
  (def device-predicted (bayes/predict device-posterior device-dynamics))
  # up = 0.9*0.875 + 0.4*0.125 = 0.8375
  (assert (approx= 0.8375 (bayes/probability device-predicted :up) 1e-6)
          "device predict runs through the kernel-0 mv lowering"))

(end-suite)
