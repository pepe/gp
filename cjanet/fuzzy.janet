(use spork/cjanet spork/misc)

# Utility
(def match-max-len 1024)

(def scores
  {:gap
   {:leading -0.005
    :trailing -0.005
    :inner -0.01}
   :match
   {:consecutive 1.0
    :slash 0.9
    :word 0.8
    :capital 0.7
    :dot 0.6}})

(defn- score [x y]
  (in (in scores x) y))

(defn- assign-ref [i v]
  ~(literal ,(string "['" (cond-> i (number? i) string/from-bytes) "'] = " v)))

(def- punctuation
  (seq [[c s] :in [["/" (score :match :slash)]
                   ["-" (score :match :word)]
                   ["_" (score :match :word)]
                   [" " (score :match :word)]
                   ["." (score :match :dot)]]]
    (assign-ref c s)))

(defn- assign-seq [r v]
  (map |(assign-ref $ v) r))

(defn- assign-lower [v]
  (assign-seq (range 97 123) v))

(defn- assign-upper [v]
  (assign-seq (range 65 91) v))

(defn- assign-digit [v]
  (assign-seq (range 48 58) v))

(defn- cstr [name]
  ~(def (,(symbol '*c name) (const uint8_t))
     (janet_string (. ,name bytes) (. ,name len))))

# C generation
(include <janet.h>)
(include <ctype.h>)

(@ define SCORE_MAX INFINITY)
(@ define SCORE_MIN -INFINITY)
(@ define "max(a, b) (((a) > (b)) ? (a) : (b))")

(cdef score-max "Maximal score" (janet_wrap_number SCORE_MAX))
(cdef score-min "Minimal score" (janet_wrap_number SCORE_MIN))

(typedef score_t double)

(typedef ascii_sizea_t (array (const size_t) 256))

(typedef ascii_scorea_t (array score_t 256))

(typedef ascii_scorem_t (array ascii_scorea_t 3))

(typedef max_len_scorea_t (array score_t ,match-max-len))

(typedef max_len_scorem_t (array max_len_scorea_t 2))

(typedef max_len_uinta_t (array uint8_t ,match-max-len))

(declare
  bonuss_index:ascii_sizea_t
  @[,;(assign-digit 1)
    ,;(assign-lower 1)
    ,;(assign-upper 2)])

(declare
  bonuss_states:ascii_scorem_t
  @[@[0]
    @[,;punctuation]
    @[,;punctuation
      ,;(assign-lower (score :match :capital))]])

(typedef
  match_struct
  (named-struct
    match_struct
    needle_len int
    haystack_len int
    lower_needle max_len_uinta_t
    lower_haystack max_len_uinta_t
    match_bonus max_len_scorea_t))

(function
  precompute_bonus :static
  "Helper that precomputes bonus for haystack."
  [(*haystack (const uint8_t)) (*match_bonus score_t)] -> void
  (def last_ch:uint8_t (literal "'/'"))
  (def i:int 0)
  (def ch:uint8_t (aref haystack i))
  (while ch
    (set (aref match_bonus i)
         (aref (aref bonuss_states
                     (aref bonuss_index ch)) last_ch))
    (set last_ch ch)
    (set ch (aref haystack (++ i)))))

(function
  setup_match_struct :static
  "Helper that sets up match struct."
  [(*match (named-struct match_struct))
   (*needle (const uint8_t))
   (*haystack (const uint8_t))] -> void
  (set match->needle_len (strlen needle))
  (set match->haystack_len (strlen haystack))
  (if (not
        (or (> match->haystack_len ,match-max-len)
            (> match->needle_len match->haystack_len)))
    (do
      (def i:int 0)
      (while (< i match->needle_len)
        (set (aref match->lower_needle i) (tolower (aref needle i)))
        (++ i))
      (set i 0)
      (while (< i match->haystack_len)
        (set (aref match->lower_haystack i) (tolower (aref haystack i)))
        (++ i))
      (precompute_bonus haystack match->match_bonus))))

(function
  match_row :static :inline
  [(*match (const (named-struct match_struct))) (row int)
   (*curr_D score_t) (*curr_M score_t)
   (*last_D (const score_t)) (*last_M (const score_t))] -> void
  (def (*match_bonus (const score_t)) match->match_bonus)
  (def prev_score:score_t SCORE_MIN)
  (def gap_score:score_t nil)
  (def i:int row)
  (if (== i (- match->needle_len 1))
    (set gap_score ,(score :gap :trailing))
    (set gap_score ,(score :gap :inner)))
  (def j:int 0)
  (while (< j match->haystack_len)
    (if (== (aref match->lower_needle i) (aref match->lower_haystack j))
      (do
        (def score:score_t SCORE_MIN)
        (if (not i)
          (set score (+ (* j ,(score :gap :leading)) (aref match_bonus j)))
          j
          (set score
               (max (+ (aref last_M (- j 1)) (aref match_bonus j))
                    (+ (aref last_D (- j 1)) ,(score :match :consecutive)))))
        (set (aref curr_D j) score)
        (set (aref curr_M j)
             (set prev_score (max score (+ prev_score gap_score)))))
      (do
        (set (aref curr_D j) SCORE_MIN)
        (set (aref curr_M j) (set prev_score (+ prev_score gap_score)))))
    ++j))

(function
  _has_match :static :inline
  "Match checking"
  [(*needle (const uint8_t)) (*haystack (const uint8_t))] -> int
  (while *needle
    (def nch:uint8_t *needle++)
    (def (accept (array (const uint8_t) 3)) (array nch (toupper nch) 0))
    (if (! (set haystack (strpbrk haystack accept)))
      (return 0))
    ++haystack)
  (return 1))

(cfunction
  hasmatch
  ```
  Checks if needle has match in haystack. Returns boolean.
  ```
  [needle:bytes haystack:bytes] -> Janet
  ,(cstr 'needle)
  ,(cstr 'haystack)
  (return (janet_wrap_boolean (_has_match cneedle chaystack))))

(function
  _score :static :inline
  "Score computation"
  [(*needle (const uint8_t)) (*haystack (const uint8_t))] -> score_t
  (if (or (not *needle) (not (_has_match needle haystack)))
    (return SCORE_MIN))
  (def (match (named-struct match_struct)) nil)
  (setup_match_struct (addr match) needle haystack)
  (def n:int match.needle_len)
  (def m:int match.haystack_len)
  (cond
    (or (> m ,match-max-len) (> n m))
    (return SCORE_MIN)
    (== n m)
    (return SCORE_MAX))
  (def D:max_len_scorem_t nil)
  (def M:max_len_scorem_t nil)
  (def *last_D:score_t (aref D 0))
  (def *last_M:score_t (aref M 0))
  (def *curr_D:score_t (aref D 1))
  (def *curr_M:score_t (aref M 1))
  (def i:int 0)
  (def *tmp:score_t nil)
  (while (< i n)
    (match_row (addr match) i curr_D curr_M last_D last_M)
    (set tmp last_D)
    (set last_D curr_D)
    (set curr_D tmp)
    (set tmp last_M)
    (set last_M curr_M)
    (set curr_M tmp)
    ++i)
  (return (aref last_M (- m 1))))

(cfunction
  score
  ```
  Computes fuzzy score for the `needle` in the `haystack.` Returns number.
  ```
  [needle:bytes haystack:bytes] -> Janet
  ,(cstr 'needle)
  ,(cstr 'haystack)
  (return (janet_wrap_number (_score cneedle chaystack))))

(cfunction
  positions
  ```
  Computes positions for the needle in the haystack. Returns array of positions.
  ```
  [needle:bytes haystack:bytes] -> Janet
  ,(cstr 'needle)
  ,(cstr 'haystack)
  (def (match (named-struct match_struct)) nil)
  (setup_match_struct (addr match) cneedle chaystack)
  (def n:int match.needle_len)
  (def m:int match.haystack_len)
  (def *arr:JanetArray (janet_array n))
  (def warr:Janet (janet_wrap_array arr))
  (if (or (not *cneedle)
          (not (_has_match cneedle chaystack)))
    (return warr))
  (cond
    (or (> m ,match-max-len) (> n m))
    (return (janet_wrap_array arr))
    (== n m)
    (do
      (def i:int 0)
      (while (< i n)
        (janet_array_push arr (janet_wrap_number i))
        (++ i))
      (return warr)))
  (def *D:max_len_scorea_t (janet_malloc (* (sizeof score_t) ,match-max-len n)))
  (def *M:max_len_scorea_t (janet_malloc (* (sizeof score_t) ,match-max-len n)))
  (def *last_D:score_t (aref D 0))
  (def *last_M:score_t (aref M 0))
  (def *curr_D:score_t (aref D 1))
  (def *curr_M:score_t (aref M 1))
  (def i:int 0)
  (while (< i n)
    (set curr_D (addr (aref (aref D i) 0)))
    (set curr_M (addr (aref (aref M i) 0)))
    (match_row (addr match) i curr_D curr_M last_D last_M)
    (set last_D curr_D)
    (set last_M curr_M)
    (++ i))
  (def match_required:int 0)
  (set i (- n 1))
  (def j:int (- m 1))
  (while (>= i 0)
    (while (>= j 0)
      (if (and (!= (aref (aref D i) j) SCORE_MIN)
               (or match_required (== (aref (aref D i) j)
                                      (aref (aref M i) j))))
        (do
          (set match_required
               (and i j (== (aref (aref M i) j)
                            (+ (aref (aref D (- i 1)) (- j 1))
                               ,(score :match :consecutive)))))
          (janet_putindex warr i (janet_wrap_number j))
          (-- j)
          (break)))
      (-- j))
    (-- i))
  (janet_free D)
  (janet_free M)
  (return warr))

(defn- malloc-guard [name type size]
  ~((def ,(symbol "*" name ":" type) (janet_malloc (* ,size (sizeof ,type))))
     (if (== ,name NULL) JANET_OUT_OF_MEMORY)))

(cfunction
  order-scores
  ```
  Takes `needle` and array of strings `str`. 
  Returns the array of strings sorted by the score.
  ```
  [needle:bytes strs:array] -> Janet
  ,(cstr 'needle)
  (def n:int32_t (-> strs count))
  (def i:int 0)
  (def count:int 0)
  ,;(malloc-guard 'res 'Janet '(* n (sizeof Janet)))
  ,;(malloc-guard 'scores 'score_t '(* (sizeof score_t) (+ n 1)))
  (set (aref scores 0) SCORE_MIN)
  (def str:JanetString)
  (while (< i n)
    (def item:Janet (aref strs->data i))
    (if (janet_checktype item JANET_BUFFER)
      (do
        (def *ub:JanetBuffer (janet_unwrap_buffer item))
        (set str (janet_string ub->data ub->count)))
      (set str (janet_unwrap_string item)))
    (def sc:score_t (_score cneedle str))
    (if (== sc SCORE_MIN) (do (++ i) (continue)))
    (def start:int 0)
    (def end:int count)
    (def mid:int (brshift end 1))
    (while (not (== mid end))
      (if (< sc (aref scores mid))
        (set mid (brshift (+ (set start mid) end 1) 1))
        (set mid (brshift (+ start (set end mid)) 1))))
    (def (ni (const int)) (+ mid 1))
    (def (sz (const int)) (+ (- i mid) 1))
    (memmove (+ scores ni)
             (+ scores mid)
             (* sz (sizeof score_t)))
    (memmove (+ res ni)
             (+ res mid)
             (* sz (sizeof Janet)))
    (set (aref scores mid) sc)
    (set (aref res mid) (janet_wrap_string str))
    (++ count)
    (++ i))

  (def resj:Janet (janet_wrap_array (janet_array_n res count)))
  (janet_free res)
  (janet_free scores)
  (return resj))

(module-entry "fuzzy")
