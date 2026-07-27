(import gp/compute)
(import ./compute/native :as compute-native)

(def- native-argument-kinds
  {:view 1 :i32 2 :f32 3 :f64 4})

(def- scalar-dtypes
  ~{:f32 true :f64 true :i32 true})

(def- buffer-access
  ~{:read true :write true :read-write true})

(def- arithmetic-operators
  {'+ true '- true '* true '/ true})

# Kernel-0.1: the math-function class admitted at the review gate after
# the Bayesian vertical, exactly the accumulated client ledger — abs and
# max from linalg reductions, exp and log from probabilistic evidence.
# Float dtypes only; semantics are pinned to the OpenCL builtins each
# function lowers to, including fmax dropping a NaN operand.
(def- math-functions
  {'abs {:arity 1 :opencl "fabs"}
   'max {:arity 2 :opencl "fmax"}
   'exp {:arity 1 :opencl "exp"}
   'log {:arity 1 :opencl "log"}})

(defn- evaluate-math
  [function values]
  (case function
    'abs (math/abs (first values))
    'exp (math/exp (first values))
    'log (math/log (first values))
    'max
    (let [[left right] values]
      (cond
        (nan? left) right
        (nan? right) left
        (max left right)))
    (errorf "cannot evaluate kernel math function %v" function)))

(defn- bracket-form?
  [form]
  (and (tuple? form)
       (= :brackets (tuple/type form))))

(defn- source-location
  [form]
  (def [line column]
    (if (tuple? form)
      (tuple/sourcemap form)
      [-1 -1]))
  {:line (if (= line -1) nil line)
   :column (if (= column -1) nil column)})

(defn- diagnose
  [diagnostics level form fmt & args]
  (def source
    (if (tuple? form)
      form
      (dyn *macro-form* form)))
  (def message (string/format fmt ;args))
  (array/push diagnostics
    {:level level
     :message message
     :source (source-location source)})
  (with-dyns [*macro-form* source]
    (maclintf level "%s" message))
  nil)

(defn- typed-symbol
  [binding]
  (unless (symbol? binding) (break nil))
  (def text (string binding))
  (def colon (string/find ":" text))
  (unless colon (break nil))
  [(symbol (slice text 0 colon))
   (keyword (slice text (+ colon 1)))])

(defn- binding-pair
  [binding diagnostics]
  (cond
    (symbol? binding)
    (or (typed-symbol binding)
        (do
          (diagnose diagnostics :strict binding
                    "kernel parameter %v has no type" binding)
          [binding :invalid]))

    (and (tuple? binding)
         (= 2 (length binding))
         (symbol? (binding 0)))
    [(binding 0) (binding 1)]

    (do
      (diagnose diagnostics :strict binding
                "kernel parameter must be `name:type` or `(name type)`")
      [(gensym) :invalid])))

(defn- normalize-shape
  [shape form diagnostics]
  (unless (bracket-form? shape)
    (diagnose diagnostics :strict form
              "buffer shape must use brackets")
    (break @[]))
  (def result @[])
  (each dimension shape
    (if (or (symbol? dimension)
            (and (number? dimension)
                 (= dimension (math/floor dimension))
                 (>= dimension 0)))
      (array/push result dimension)
      (do
        (diagnose diagnostics :strict form
                  "buffer dimension %v must be a symbol or non-negative integer"
                  dimension)
        (array/push result 0))))
  result)

(defn- normalize-parameter
  [binding diagnostics]
  (def [name type-form] (binding-pair binding diagnostics))
  (cond
    (get scalar-dtypes type-form)
    {:kind :scalar
     :name name
     :dtype type-form
     :source (source-location binding)}

    (and (tuple? type-form)
         (= 'buffer (get type-form 0)))
    (do
      (def dtype (get type-form 1))
      (def shape (get type-form 2))
      (def access (get type-form 3))
      (unless (= 4 (length type-form))
        (diagnose diagnostics :strict type-form
                  "buffer type is `(buffer dtype shape access)`"))
      (unless (get scalar-dtypes dtype)
        (diagnose diagnostics :strict type-form
                  "unsupported buffer dtype %v" dtype))
      (unless (get buffer-access access)
        (diagnose diagnostics :strict type-form
                  "unsupported buffer access %v" access))
      {:kind :buffer
       :name name
       :dtype (if (get scalar-dtypes dtype) dtype :invalid)
       :shape (normalize-shape shape type-form diagnostics)
       :access (if (get buffer-access access) access :invalid)
       :source (source-location binding)})

    (do
      (diagnose diagnostics :strict binding
                "unsupported kernel parameter type %v" type-form)
      {:kind :invalid
       :name name
       :dtype :invalid
       :source (source-location binding)})))

(defn- parameter-environment
  [parameters diagnostics]
  (def environment @{})
  (each parameter parameters
    (def name (parameter :name))
    (if (has-key? environment name)
      (diagnose diagnostics :strict parameter
                "duplicate kernel parameter %v" name)
      (put environment name parameter)))
  environment)

(defn- validate-symbolic-shapes
  [parameters environment diagnostics]
  (each parameter parameters
    (when (= :buffer (parameter :kind))
      (each dimension (parameter :shape)
        (when (symbol? dimension)
          (def shape-parameter (get environment dimension))
          (cond
            (nil? shape-parameter)
            (diagnose diagnostics :strict parameter
                      "unknown symbolic dimension %v" dimension)

            (not= :scalar (shape-parameter :kind))
            (diagnose diagnostics :strict parameter
                      "buffer parameter %v cannot be a dimension" dimension)

            (not= :i32 (shape-parameter :dtype))
            (diagnose diagnostics :strict parameter
                      "symbolic dimension %v must have dtype :i32" dimension))))))
  nil)

(defn- exact-parallel-indexes?
  [indexes parallel-variables]
  (and (= (length indexes) (length parallel-variables))
       (all identity
         (map |(and (= :ref (get $0 :op))
                    (= $1 (get $0 :name)))
              indexes parallel-variables))))

(defmacro- install-recursive :flycheck
  [name arguments & body]
  ~(set ,name (fn ,name ,arguments ,;body)))

(var- normalize-expression nil)
(var- normalize-statement nil)

(defn- merged-expression-dtype
  [nodes form diagnostics]
  (def concrete @[])
  (each node nodes
    (def dtype (get node :dtype :invalid))
    (when (and (not= :constant (node :op))
               (not= :invalid dtype)
               (not (find |(= dtype $) concrete)))
      (array/push concrete dtype)))
  (when (> (length concrete) 1)
    (diagnose diagnostics :strict form
              "arithmetic mixes incompatible dtypes %v"
              concrete))
  (if (empty? concrete)
    (get (first nodes) :dtype :invalid)
    (first concrete)))

(defn- require-i32-expression
  [node role form diagnostics]
  (unless (= :i32 (get node :dtype))
    (diagnose diagnostics :strict form
              "%s must have dtype :i32" role))
  node)

(defn- normalize-indexes
  [forms environment diagnostics context]
  (unless (bracket-form? forms)
    (diagnose diagnostics :strict forms
              "buffer indexes must use brackets")
    (break @[]))
  (map |(require-i32-expression
          (normalize-expression $ environment diagnostics context)
          "buffer index" forms diagnostics)
       forms))

(defn- normalize-load
  [form environment diagnostics context]
  (def name (get form 1))
  (def parameter (and (symbol? name) (get environment name)))
  (unless (and parameter (= :buffer (parameter :kind)))
    (diagnose diagnostics :strict form
              "load target %v is not a buffer parameter" name))
  (def indexes
    (normalize-indexes (get form 2) environment diagnostics context))
  (when (and parameter
             (= :buffer (parameter :kind))
             (not= (length indexes) (length (parameter :shape))))
    (diagnose diagnostics :strict form
              "load from %v has %d indexes, expected %d"
              name (length indexes) (length (parameter :shape))))
  (when (and parameter (= :write (parameter :access)))
    (diagnose diagnostics :strict form
              "write-only buffer %v cannot be loaded" name))
  (def parallel-variables (get context :parallel-variables []))
  (when (and parameter
             (= :read-write (parameter :access))
             (not (empty? parallel-variables))
             (not (exact-parallel-indexes?
                    indexes parallel-variables)))
    (diagnose diagnostics :strict form
              "read-write buffer %v must use the exact parallel indexes"
              name))
  {:op :load
   :buffer name
   :indexes indexes
   :dtype (if parameter (parameter :dtype) :invalid)
   :source (source-location form)})

(defn- normalize-reduce
  [form environment diagnostics context]
  (def operator (get form 1))
  (def binary-math?
    (and (get math-functions operator)
         (= 2 ((math-functions operator) :arity))))
  (unless (or (get arithmetic-operators operator) binary-math?)
    (diagnose diagnostics :strict form
              "unsupported reduction operator %v" operator))
  (def binding (get form 3))
  (def binding-valid?
    (and (bracket-form? binding)
               (= 3 (length binding))
         (symbol? (get binding 0))))
  (unless binding-valid?
    (diagnose diagnostics :strict form
              "reduction binding must be `[index start end]`"))
  (def index-name
    (if binding-valid?
      (get binding 0)
      (gensym)))
  (def safe-binding
    (if binding-valid?
      binding
      [index-name 0 0]))
  (when (has-key? environment index-name)
    (diagnose diagnostics :strict form
              "reduction index %v shadows an existing binding" index-name))
  (def nested (table/clone environment))
  (put nested index-name
       {:kind :index :name index-name :dtype :i32})
  (def initial
    (normalize-expression
      (get form 2) environment diagnostics context))
  (def start
    (require-i32-expression
      (normalize-expression
        (get safe-binding 1) environment diagnostics context)
      "reduction start" form diagnostics))
  (def end
    (require-i32-expression
      (normalize-expression
        (get safe-binding 2) environment diagnostics context)
      "reduction end" form diagnostics))
  (def expression
    (normalize-expression
      (get form 4) nested diagnostics context))
  (def dtype
    (merged-expression-dtype [initial expression] form diagnostics))
  (when (and binary-math?
             (not (or (= :f32 dtype) (= :f64 dtype))))
    (diagnose diagnostics :strict form
              "math reduction %v requires :f32 or :f64 operands" operator))
  {:op :reduce
   :operator operator
   :initial initial
   :index index-name
   :start start
   :end end
   :expression expression
   :dtype dtype
   :source (source-location form)})

(install-recursive normalize-expression
  [form environment diagnostics context]
  (cond
    (number? form)
    {:op :constant
     :value form
     :dtype (if (= form (math/floor form)) :i32 :number)
     :source (source-location form)}

    (symbol? form)
    (if-let [binding (get environment form)]
      (if (= :buffer (binding :kind))
        (do
          (diagnose diagnostics :strict form
                    "buffer %v must be accessed with load" form)
          {:op :invalid :source (source-location form)})
        {:op :ref
         :name form
         :dtype (binding :dtype)
         :source (source-location form)})
      (do
        (diagnose diagnostics :strict form
                  "unbound kernel name %v" form)
        {:op :invalid :source (source-location form)}))

    (not (tuple? form))
    (do
      (diagnose diagnostics :strict form
                "invalid kernel expression %v" form)
      {:op :invalid :source (source-location form)})

    (empty? form)
    (do
      (diagnose diagnostics :strict form "empty kernel expression")
      {:op :invalid :source (source-location form)})

    (= 'load (form 0))
    (if (= 3 (length form))
      (normalize-load form environment diagnostics context)
      (do
        (diagnose diagnostics :strict form
                  "load is `(load buffer [indexes...])`")
        {:op :invalid :source (source-location form)}))

    (= 'reduce (form 0))
    (if (= 5 (length form))
      (normalize-reduce form environment diagnostics context)
      (do
        (diagnose diagnostics :strict form
                  "reduce is `(reduce operator initial [index start end] expression)`")
        {:op :invalid :source (source-location form)}))

    (get arithmetic-operators (form 0))
    (do
      (when (< (length form) 3)
        (diagnose diagnostics :strict form
                  "arithmetic operator %v needs at least two operands"
                  (form 0)))
      (def arguments
        (map |(normalize-expression
                $ environment diagnostics context)
             (drop 1 form)))
      {:op :call
       :operator (form 0)
       :arguments arguments
       :dtype (merged-expression-dtype
                arguments form diagnostics)
       :source (source-location form)})

    (get math-functions (form 0))
    (do
      (def definition (math-functions (form 0)))
      (unless (= (definition :arity) (- (length form) 1))
        (diagnose diagnostics :strict form
                  "math function %v takes %d arguments"
                  (form 0) (definition :arity)))
      (def arguments
        (map |(normalize-expression
                $ environment diagnostics context)
             (drop 1 form)))
      (def dtype (merged-expression-dtype arguments form diagnostics))
      (unless (or (= :f32 dtype) (= :f64 dtype))
        (diagnose diagnostics :strict form
                  "math function %v requires :f32 or :f64 operands"
                  (form 0)))
      {:op :math
       :function (form 0)
       :arguments arguments
       :dtype dtype
       :source (source-location form)})

    (do
      (diagnose diagnostics :strict form
                "unknown kernel expression %v" (form 0))
      {:op :invalid :source (source-location form)})))

(defn- normalize-store
  [form environment diagnostics context]
  (def name (get form 1))
  (def parameter (and (symbol? name) (get environment name)))
  (unless (and parameter (= :buffer (parameter :kind)))
    (diagnose diagnostics :strict form
              "store target %v is not a buffer parameter" name))
  (when (and parameter (= :read (parameter :access)))
    (diagnose diagnostics :strict form
              "read-only buffer %v cannot be stored" name))
  (def indexes
    (normalize-indexes (get form 2) environment diagnostics context))
  (when (and parameter
             (not= (length indexes) (length (parameter :shape))))
    (diagnose diagnostics :strict form
              "store to %v has %d indexes, expected %d"
              name (length indexes) (length (parameter :shape))))
  (def parallel-variables (get context :parallel-variables []))
  (when (and (not (empty? parallel-variables))
             (not (exact-parallel-indexes?
                    indexes parallel-variables)))
    (diagnose diagnostics :strict form
              "parallel store to %v must use the exact parallel indexes"
              name))
  (def value
    (normalize-expression
      (get form 3) environment diagnostics context))
  (when (and parameter
             (not= :constant (value :op))
             (not= :invalid (get value :dtype :invalid))
             (not= (parameter :dtype) (value :dtype)))
    (diagnose diagnostics :strict form
              "store to %v has dtype %v, expected %v"
              name (value :dtype) (parameter :dtype)))
  {:op :store
   :buffer name
   :indexes indexes
   :value value
   :source (source-location form)})

(defn- normalize-loop
  [kind form environment diagnostics context]
  (def binding (get form 1))
  (def binding-valid?
    (and (bracket-form? binding)
               (= 3 (length binding))
         (symbol? (get binding 0))))
  (unless binding-valid?
    (diagnose diagnostics :strict form
              "%v binding must be `[index start end]`" kind))
  (def index-name
    (if binding-valid?
      (get binding 0)
      (gensym)))
  (def safe-binding
    (if binding-valid?
      binding
      [index-name 0 0]))
  (when (has-key? environment index-name)
    (diagnose diagnostics :strict form
              "%v index %v shadows an existing binding"
              kind index-name))
  (def nested (table/clone environment))
  (put nested index-name
       {:kind :index :name index-name :dtype :i32})
  (def parallel-variables
    (if (= :parallel kind)
      [;(get context :parallel-variables []) index-name]
      (get context :parallel-variables [])))
  (def start
    (require-i32-expression
      (normalize-expression
        (get safe-binding 1) environment diagnostics context)
      (string kind " start") form diagnostics))
  (def end
    (require-i32-expression
      (normalize-expression
        (get safe-binding 2) environment diagnostics context)
      (string kind " end") form diagnostics))
  (when (empty? (drop 2 form))
    (diagnose diagnostics :strict form
              "%v body cannot be empty" kind))
  {:op kind
   :index index-name
   :start start
   :end end
   :body
   {:op :block
    :statements
    (map |(normalize-statement
            $ nested diagnostics
            {:parallel-variables parallel-variables})
         (drop 2 form))
    :source (source-location form)}
   :source (source-location form)})

(install-recursive normalize-statement
  [form environment diagnostics context]
  (cond
    (not (tuple? form))
    (do
      (diagnose diagnostics :strict form
                "kernel statement must be a form")
      {:op :invalid :source (source-location form)})

    (= 'store! (get form 0))
    (if (= 4 (length form))
      (normalize-store form environment diagnostics context)
      (do
        (diagnose diagnostics :strict form
                  "store! is `(store! buffer [indexes...] value)`")
        {:op :invalid :source (source-location form)}))

    (= 'parallel (get form 0))
    (normalize-loop :parallel form environment diagnostics context)

    (= 'serial (get form 0))
    (normalize-loop :serial form environment diagnostics context)

    (do
      (diagnose diagnostics :strict form
                "unknown kernel statement %v" (get form 0))
      {:op :invalid :source (source-location form)})))

(defn- analyze-definition
  [name parameter-forms body source]
  (def diagnostics @[])
  (unless (bracket-form? parameter-forms)
    (diagnose diagnostics :strict source
              "kernel parameters must use brackets"))
  (def parameters
    (if (bracket-form? parameter-forms)
      (map |(normalize-parameter $ diagnostics) parameter-forms)
      @[]))
  (def environment
    (parameter-environment parameters diagnostics))
  (validate-symbolic-shapes parameters environment diagnostics)
  (when (empty? body)
    (diagnose diagnostics :strict source
              "kernel body cannot be empty"))
  (freeze
    {:gp/kernel true
     :name name
     :parameters parameters
     :ir {:op :block
          :statements
          (map |(normalize-statement
                  $ environment diagnostics
                  {:parallel-variables []})
               body)
          :source (source-location source)}
     :diagnostics diagnostics}))

(defmacro defkernel :flycheck
  "Define a typed kernel and retain its normalized, source-mapped IR."
  [name parameters & body]
  (unless (symbol? name)
    (maclintf :strict "kernel name must be a symbol")
    (break nil))
  (def kernel
    (analyze-definition name parameters body (dyn *macro-form*)))
  ~(def ,name (quote ,kernel)))

(defn kernel?
  "Return true when `value` is a normalized gp kernel."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/kernel))))

(defn name
  "Return the kernel's declared name."
  [kernel]
  (assert (kernel? kernel) "expected a gp kernel")
  (kernel :name))

(defn parameters
  "Return the normalized parameter descriptions."
  [kernel]
  (assert (kernel? kernel) "expected a gp kernel")
  (kernel :parameters))

(defn ir
  "Return the normalized, source-mapped kernel IR."
  [kernel]
  (assert (kernel? kernel) "expected a gp kernel")
  (kernel :ir))

(defn diagnostics
  "Return static diagnostics collected while defining the kernel."
  [kernel]
  (assert (kernel? kernel) "expected a gp kernel")
  (kernel :diagnostics))

(defn valid?
  "Return true when the kernel has no strict diagnostics."
  [kernel]
  (assert (kernel? kernel) "expected a gp kernel")
  (var strict? false)
  (each diagnostic (kernel :diagnostics)
    (when (= :strict (diagnostic :level))
      (set strict? true)))
  (not strict?))

(defn- runtime-binding
  [bindings name]
  (cond
    (has-key? bindings name) (get bindings name)
    (has-key? bindings (keyword name)) (get bindings (keyword name))
    (errorf "missing kernel binding %v" name)))

(defn- valid-i32?
  [value]
  (and (number? value)
       (= value (math/floor value))
       (>= value -2147483648)
       (<= value 2147483647)))

(defn- validate-runtime-bindings
  [kernel bindings &opt required-engine]
  (unless (dictionary? bindings)
    (error "kernel bindings must be a table or struct"))
  (def environment @{})
  (each parameter (kernel :parameters)
    (def parameter-name (parameter :name))
    (def value (runtime-binding bindings parameter-name))
    (case (parameter :kind)
      :scalar
      (do
        (unless (number? value)
          (errorf "kernel scalar %v must be a number" parameter-name))
        (when (and (= :i32 (parameter :dtype))
                   (not (valid-i32? value)))
          (errorf "kernel scalar %v is outside :i32" parameter-name)))

      :buffer
      (do
        (def [view? dtype] (protect (compute/dtype value)))
        (unless view?
          (errorf "kernel buffer %v must be a compute view"
                  parameter-name))
        (unless (= dtype (parameter :dtype))
          (errorf "kernel buffer %v has dtype %v, expected %v"
                  parameter-name dtype (parameter :dtype)))
        (when (and required-engine
                   (not= required-engine
                         (compute/engine-name (compute/engine value))))
          (errorf
            "kernel evaluation requires %s buffer %v"
            required-engine parameter-name)))

      (errorf "kernel %v is invalid" (kernel :name)))
    (put environment parameter-name value))

  (each parameter (kernel :parameters)
    (when (= :buffer (parameter :kind))
      (def expected
        (map |(if (symbol? $)
                (get environment $)
                $)
             (parameter :shape)))
      (each dimension expected
        (unless (and (valid-i32? dimension) (>= dimension 0))
          (errorf "kernel buffer %v has an invalid dimension %v"
                  (parameter :name) dimension)))
      (unless (deep= expected
                     (compute/shape (get environment
                                         (parameter :name))))
        (errorf "kernel buffer %v has shape %v, expected %v"
                (parameter :name)
                (compute/shape (get environment
                                    (parameter :name)))
                expected))))

  (def buffers
    (filter |(= :buffer ($ :kind)) (kernel :parameters)))
  (eachp [left-index left] buffers
    (each right (drop (+ left-index 1) buffers)
      (when (and (= (compute/storage-id
                      (get environment (left :name)))
                    (compute/storage-id
                      (get environment (right :name))))
                 (or (not= :read (left :access))
                     (not= :read (right :access))))
        (errorf
          "writable kernel buffers %v and %v cannot alias in kernel-0"
          (left :name) (right :name)))))
  environment)

(defn- apply-operator
  [operator values]
  (if (get math-functions operator)
    (evaluate-math operator values)
    (do
      (def initial (first values))
      (def rest (drop 1 values))
      (case operator
        '+ (reduce + initial rest)
        '- (reduce - initial rest)
        '* (reduce * initial rest)
        '/ (reduce / initial rest)
        (errorf "cannot evaluate kernel operator %v" operator)))))

(var- evaluate-expression nil)
(var- evaluate-statement nil)

(defn- logical-index
  [view index-nodes environment]
  (def shape (compute/shape view))
  (unless (= (length shape) (length index-nodes))
    (error "kernel index rank changed after validation"))
  (var flat 0)
  (eachp [axis index-node] index-nodes
    (def index (evaluate-expression index-node environment))
    (unless (and (number? index)
                 (= index (math/floor index))
                 (>= index 0)
                 (< index (shape axis)))
      (errorf "kernel index %v is outside axis %d with extent %d"
              index axis (shape axis)))
    (set flat (+ (* flat (shape axis)) index)))
  flat)

(install-recursive evaluate-expression
  [node environment]
  (case (node :op)
    :constant (node :value)
    :ref (get environment (node :name))
    :call
    (apply-operator
      (node :operator)
      (map |(evaluate-expression $ environment)
           (node :arguments)))
    :math
    (evaluate-math
      (node :function)
      (map |(evaluate-expression $ environment)
           (node :arguments)))
    :load
    (do
      (def view (get environment (node :buffer)))
      (compute/get
        view
        (logical-index view (node :indexes) environment)))
    :reduce
    (do
      (var accumulator
        (evaluate-expression (node :initial) environment))
      (def start
        (evaluate-expression (node :start) environment))
      (def end
        (evaluate-expression (node :end) environment))
      (unless (and (valid-i32? start) (valid-i32? end))
        (error "kernel reduction bounds must be :i32 values"))
      (var index start)
      (while (< index end)
        (put environment (node :index) index)
        (set accumulator
             (apply-operator
               (node :operator)
               [accumulator
                (evaluate-expression
                  (node :expression) environment)]))
        (++ index))
      (put environment (node :index) nil)
      accumulator)
    (errorf "cannot evaluate invalid kernel expression %v"
            (node :op))))

(defn- evaluate-block
  [node environment]
  (each statement (node :statements)
    (evaluate-statement statement environment))
  nil)

(defn- evaluate-loop
  [node environment]
  (def start (evaluate-expression (node :start) environment))
  (def end (evaluate-expression (node :end) environment))
  (unless (and (valid-i32? start) (valid-i32? end))
    (error "kernel loop bounds must be :i32 values"))
  (var index start)
  (while (< index end)
    (put environment (node :index) index)
    (evaluate-block (node :body) environment)
    (++ index))
  (put environment (node :index) nil)
  nil)

(install-recursive evaluate-statement
  [node environment]
  (case (node :op)
    :store
    (do
      (def view (get environment (node :buffer)))
      (compute/put!
        view
        (logical-index view (node :indexes) environment)
        (evaluate-expression (node :value) environment)))
    :parallel (evaluate-loop node environment)
    :serial (evaluate-loop node environment)
    :block (evaluate-block node environment)
    (errorf "cannot evaluate invalid kernel statement %v"
            (node :op))))

(defn run!
  "Validate bindings and execute a kernel synchronously on the C++ reference engine."
  [kernel bindings]
  (unless (kernel? kernel)
    (error "expected a gp kernel"))
  (unless (valid? kernel)
    (errorf "kernel %v has strict diagnostics" (kernel :name)))
  (def environment
    (validate-runtime-bindings kernel bindings "cpp"))
  (evaluate-block (kernel :ir) environment)
  bindings)

(def- opencl-types
  {:f32 "float" :f64 "double" :i32 "int"})

(defn- c-name
  [prefix value]
  (def output (buffer prefix))
  (each byte (string value)
    (if (or (and (>= byte 48) (<= byte 57))
            (and (>= byte 65) (<= byte 90))
            (and (>= byte 97) (<= byte 122)))
      (buffer/push-byte output byte)
      (buffer/push-string output
        (string/format "_%02x" byte))))
  (string output))

(defn- c-type
  [dtype]
  (or (opencl-types dtype)
      (errorf "cannot lower unsupported kernel dtype %v" dtype)))

(defn- indent-lines
  [text depth]
  (def prefix (string/repeat "  " depth))
  (string/join
    (map |(if (empty? $) $ (string prefix $))
         (string/split "\n" text))
    "\n"))

(defn- expression-host?
  [node scalar-names]
  (case (node :op)
    :constant true
    :ref (get scalar-names (node :name) false)
    :call (all |(expression-host? $ scalar-names)
               (node :arguments))
    false))

(defn- parallel-domains
  [kernel]
  (def domains @[])
  (def scalar-names @{})
  (each parameter (kernel :parameters)
    (when (= :scalar (parameter :kind))
      (put scalar-names (parameter :name) true)))
  (var walk nil)
  (set walk
    (fn walk [node depth]
      (case (node :op)
        :block
        (each statement (node :statements)
          (walk statement depth))

        :parallel
        (do
          (unless (and (expression-host? (node :start) scalar-names)
                       (expression-host? (node :end) scalar-names))
            (error
              "parallel bounds must use only scalar parameters and arithmetic"))
          (when (>= depth 3)
            (error "OpenCL kernels support at most three parallel axes"))
          (def domain [(node :start) (node :end)])
          (if-let [existing (get domains depth)]
            (unless (deep= existing domain)
              (errorf
                "parallel axis %d has inconsistent bounds" depth))
            (array/push domains domain))
          (walk (node :body) (+ depth 1)))

        :serial (walk (node :body) depth)
        nil)))
  (walk (kernel :ir) 0)
  domains)

(defn- lower-opencl
  [kernel]
  (unless (kernel? kernel) (error "expected a gp kernel"))
  (unless (valid? kernel)
    (errorf "kernel %v has strict diagnostics" (kernel :name)))
  (def domains (parallel-domains kernel))
  (def names @{})
  (each parameter (kernel :parameters)
    (put names (parameter :name)
         (c-name "gp_p_" (parameter :name))))
  (def state @{:temporary 0 :names names})

  (defn fresh [prefix]
    (def value (state :temporary))
    (put state :temporary (+ value 1))
    (string "gp_" prefix "_" value))

  (var emit-expression nil)
  (set emit-expression
    (fn emit-expression [node depth]
      (case (node :op)
        :constant ["" (string (node :value))]
        :ref ["" (or (get names (node :name))
                     (c-name "gp_i_" (node :name)))]
        :call
        (do
          (def lowered
            (map |(emit-expression $ depth) (node :arguments)))
          [(string/join (map first lowered) "")
           (string "("
             (string/join (map |(get $ 1) lowered)
                          (string " " (node :operator) " "))
             ")")])
        :math
        (do
          (def lowered
            (map |(emit-expression $ depth) (node :arguments)))
          [(string/join (map first lowered) "")
           (string ((math-functions (node :function)) :opencl)
                   "("
                   (string/join (map |(get $ 1) lowered) ", ")
                   ")")])
        :load
        (do
          (def lowered
            (map |(emit-expression $ depth) (node :indexes)))
          (def buffer-name (get names (node :buffer)))
          (def terms
            (map |(string "((long)(" (get $ 1)
                         ") * " buffer-name "_stride" $1 ")")
                 lowered (range 0 (length lowered))))
          [(string/join (map first lowered) "")
           (string buffer-name "_data[(ulong)(" buffer-name "_offset"
                   (if (empty? terms)
                     ""
                     (string " + " (string/join terms " + ")))
                   ")]")])
        :reduce
        (do
          (def initial (emit-expression (node :initial) depth))
          (def start (emit-expression (node :start) depth))
          (def end (emit-expression (node :end) depth))
          (def accumulator (fresh "reduce"))
          (def index-name (c-name "gp_i_" (node :index)))
          (put names (node :index) index-name)
          (def expression (emit-expression (node :expression) (+ depth 1)))
          (put names (node :index) nil)
          (def prelude
            (string (first initial) (first start) (first end)
              (indent-lines
                (string (c-type (node :dtype)) " " accumulator " = "
                        (get initial 1) ";\n"
                        "for (int " index-name " = " (get start 1)
                        "; " index-name " < " (get end 1)
                        "; ++" index-name ") {\n"
                        (first expression)
                        (indent-lines
                          (if-let [definition (get math-functions (node :operator))]
                            (string accumulator " = " (definition :opencl)
                                    "(" accumulator ", "
                                    (get expression 1) ");\n")
                            (string accumulator " = " accumulator " "
                                    (node :operator) " "
                                    (get expression 1) ";\n"))
                          1)
                        "}\n")
                depth)))
          [prelude accumulator])
        (errorf "cannot lower invalid kernel expression %v"
                (node :op)))))

  (var emit-statement nil)
  (defn emit-block [node depth parallel-depth]
    (string/join
      (map |(emit-statement $ depth parallel-depth)
           (node :statements))
      ""))
  (set emit-statement
    (fn emit-statement [node depth parallel-depth]
      (case (node :op)
        :store
        (do
          (def indexes
            (map |(emit-expression $ depth) (node :indexes)))
          (def value (emit-expression (node :value) depth))
          (def buffer-name (get names (node :buffer)))
          (def terms
            (map |(string "((long)(" (get $ 1)
                         ") * " buffer-name "_stride" $1 ")")
                 indexes (range 0 (length indexes))))
          (string (string/join (map first indexes) "")
                  (first value)
                  (indent-lines
                    (string buffer-name "_data[(ulong)("
                            buffer-name "_offset"
                            (if (empty? terms)
                              ""
                              (string " + " (string/join terms " + ")))
                            ")] = " (get value 1) ";\n")
                    depth)))
        :serial
        (do
          (def start (emit-expression (node :start) depth))
          (def end (emit-expression (node :end) depth))
          (def index-name (c-name "gp_i_" (node :index)))
          (put names (node :index) index-name)
          (def body (emit-block (node :body) (+ depth 1) parallel-depth))
          (put names (node :index) nil)
          (string (first start) (first end)
            (indent-lines
              (string "for (int " index-name " = " (get start 1)
                      "; " index-name " < " (get end 1)
                      "; ++" index-name ") {\n")
              depth)
            body
            (indent-lines "}\n" depth)))
        :parallel
        (do
          (def start (emit-expression (node :start) depth))
          (def end (emit-expression (node :end) depth))
          (def index-name (c-name "gp_i_" (node :index)))
          (put names (node :index) index-name)
          (def body
            (emit-block (node :body) (+ depth 1)
                        (+ parallel-depth 1)))
          (put names (node :index) nil)
          (string (first start) (first end)
            (indent-lines
              (string "int " index-name " = (int)(" (get start 1)
                      ") + (int)get_global_id(" parallel-depth ");\n"
                      "if (" index-name " < (int)(" (get end 1) ")) {\n")
              depth)
            body
            (indent-lines "}\n" depth)))
        (errorf "cannot lower invalid kernel statement %v"
                (node :op)))))

  (def entry-name (c-name "gp_kernel_" (kernel :name)))
  (def arguments @[])
  (var needs-f64 false)
  (each parameter (kernel :parameters)
    (def parameter-name (get names (parameter :name)))
    (when (= :f64 (parameter :dtype)) (set needs-f64 true))
    (case (parameter :kind)
      :scalar
      (array/push arguments
        (string (c-type (parameter :dtype)) " " parameter-name))
      :buffer
      (do
        (array/push arguments
          (string "__global "
                  (if (= :read (parameter :access)) "const " "")
                  (c-type (parameter :dtype)) " *" parameter-name "_data"))
        (array/push arguments
          (string "ulong " parameter-name "_offset"))
        (eachp [axis _] (parameter :shape)
          (array/push arguments
            (string "long " parameter-name "_stride" axis))))))
  (def body (emit-block (kernel :ir) 1 0))
  {:entry-name entry-name
   :domains domains
   :source
   (string
     "/* gp kernel-0: " (kernel :name) " */\n"
     (if needs-f64
       "#pragma OPENCL EXTENSION cl_khr_fp64 : enable\n"
       "")
     "__kernel void " entry-name "(\n  "
     (string/join arguments ",\n  ")
     ") {\n" body "}\n")})

(defn opencl-source
  "Return deterministic, inspectable OpenCL C for `kernel`."
  [kernel]
  ((lower-opencl kernel) :source))

(defn- stable-source-key
  [text]
  (var hash 5381)
  (each byte text
    (set hash (mod (+ (* hash 33) byte) 4294967296)))
  (string/format "kernel-0-%08x" hash))

(defn compile
  "Compile `kernel` for an OpenCL engine and retain source metadata."
  [engine kernel]
  (unless (= "opencl" (compute/engine-name engine))
    (error "kernel compilation currently requires an OpenCL engine"))
  (def lowered (lower-opencl kernel))
  (def source (lowered :source))
  (freeze
    {:gp/compiled-kernel true
     :definition kernel
     :engine-name (compute/engine-name engine)
     :device-name (compute/engine-device-name engine)
     :entry-name (lowered :entry-name)
     :source source
     :cache-key
     (stable-source-key
       (string "kernel-0\n"
               (compute/engine-device-name engine) "\n" source))
     :domains (lowered :domains)
     :native
     (compute-native/compile-kernel
       engine (lowered :entry-name) source)}))

(defn compiled?
  "Return true when `value` is compiled kernel metadata."
  [value]
  (and (dictionary? value)
       (= true (get value :gp/compiled-kernel))))

(defn source
  "Return the OpenCL C retained by a compiled kernel."
  [compiled]
  (assert (compiled? compiled) "expected a compiled kernel")
  (compiled :source))

(defn cache-key
  "Return the deterministic compiler/device/source cache identity."
  [compiled]
  (assert (compiled? compiled) "expected a compiled kernel")
  (compiled :cache-key))

(defn- launch-extents
  [compiled environment]
  (if (empty? (compiled :domains))
    @[1]
    (map
      (fn [domain]
        (def start (evaluate-expression (domain 0) environment))
        (def end (evaluate-expression (domain 1) environment))
        (max 0 (- end start)))
      (compiled :domains))))

(defn launch
  "Validate bindings, enqueue `compiled` on `queue`, and return an event."
  [compiled queue bindings & dependencies]
  (unless (compiled? compiled) (error "expected a compiled kernel"))
  (when (compute-native/kernel-closed? (compiled :native))
    (error "compiled kernel is closed"))
  (def definition (compiled :definition))
  (def environment
    (validate-runtime-bindings definition bindings "opencl"))
  (def kinds @[])
  (def values @[])
  (each parameter (definition :parameters)
    (array/push kinds
      (if (= :buffer (parameter :kind))
        :view
        (parameter :dtype)))
    (array/push values (get environment (parameter :name))))
  (compute-native/enqueue-kernel
    queue (compiled :native)
    (launch-extents compiled environment)
    (map |(or (get native-argument-kinds $)
              (errorf "unsupported kernel argument kind %v" $))
         kinds)
    values
    (array ;dependencies)))

(defn close
  "Release the native program owned by `compiled`."
  [compiled]
  (assert (compiled? compiled) "expected a compiled kernel")
  (compute-native/close-kernel (compiled :native)))

(defn closed?
  "Return true when `compiled` has been explicitly closed."
  [compiled]
  (assert (compiled? compiled) "expected a compiled kernel")
  (compute-native/kernel-closed? (compiled :native)))
