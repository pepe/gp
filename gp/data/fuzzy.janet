(import spork/misc :prefix "")
(import spork/cjanet :prefix "" :fresh true)

(include <janet.h>)
(include <ctype.h>)
(@ define SCORE_MAX INFINITY)
(@ define SCORE_MIN -INFINITY)
(@ define MATCH_MAX_LEN 1024)
(@ define SCORE_GAP_LEADING -0.005)
(@ define SCORE_GAP_TRAILING -0.005)
(@ define SCORE_GAP_INNER -0.01)
(@ define SCORE_MATCH_CONSECUTIVE 1.0)
(@ define SCORE_MATCH_SLASH 0.9)
(@ define SCORE_MATCH_WORD 0.8)
(@ define SCORE_MATCH_CAPITAL 0.7)
(@ define SCORE_MATCH_DOT 0.6)

(defn- assign-ref [i v]
  ~(literal ,(string "['" (cond-> i (number? i) string/from-bytes) "'] = " v)))

(def- punctuation
  (seq [[c s] :in [["/" "SCORE_MATCH_SLASH"]
                   ["-" "SCORE_MATCH_WORD"]
                   ["_" "SCORE_MATCH_WORD"]
                   [" " "SCORE_MATCH_WORD"]
                   ["." "SCORE_MATCH_DOT"]]]
    (assign-ref c s)))

(defn- assign-lower [v]
  (seq [c :range [97 123]] (assign-ref c v)))

(defn- assign-upper [v]
  (seq [c :range [65 91]] (assign-ref c v)))

(defn- assign-digit [v]
  (seq [c :range [48 58]] (assign-ref c v)))

(typedef score_t double)

(declare
  (bonuss_index (array (const size_t) 256))
  @[,;(assign-digit 1)
    ,;(assign-lower 1)
    ,;(assign-upper 2)])


(declare
  (bonuss_states (array (const score_t) (literal "3][256")))
  @[@[0]
    @[,;punctuation]
    @[,;punctuation
      ,;(assign-lower "SCORE_MATCH_CAPITAL")]])

(typedef match_struct
         (named-struct
           match_struct
           needle_len int
           haystack_len int
           "lower_needle[MATCH_MAX_LEN]" uint8_t
           "lower_haystack[MATCH_MAX_LEN]" uint8_t
           "match_bonus[MATCH_MAX_LEN]" score_t))

(function precompute_bonus :static
          "Helper that precomputes bonus for haystack."
          [(*haystack (const uint8_t)) (*match_bonus score_t)] -> void
          (def (last_ch uint8_t) (literal "'/'"))
          (def (i int) 0)
          (while (aref haystack i)
            (def (ch uint8_t) (aref haystack i))
            (set (aref match_bonus i)
                 (aref (aref bonuss_states
                             (aref bonuss_index ch)) last_ch))
            (set last_ch ch)
            ++i))

(function setup_match_struct :static
          "Helper that sets up match struct."
          [(*match (named-struct match_struct))
           (*needle (const uint8_t)) (*haystack (const uint8_t))] -> void
          (set match->needle_len (strlen needle))
          (set match->haystack_len (strlen haystack))
          (if (not
                (or (> match->haystack_len MATCH_MAX_LEN)
                    (> match->needle_len match->haystack_len)))
            (do
              (def (i int) 0)
              (while (< i match->needle_len)
                (set (aref match->lower_needle i) (tolower (aref needle i)))
                (++ i))
              (set i 0)
              (while (< i match->haystack_len)
                (set (aref match->lower_haystack i) (tolower (aref haystack i)))
                (++ i))
              (precompute_bonus haystack match->match_bonus))))

(function match_row :static :inline
          [(*match (const (named-struct match_struct))) (row int)
           (*curr_D score_t) (*curr_M score_t)
           (*last_D (const score_t)) (*last_M (const score_t))] -> void
          (def (i int) row)
          (def (*match_bonus (const score_t)) match->match_bonus)
          (def (prev_score score_t) SCORE_MIN)
          (def (gap_score score_t) nil)
          (if (== i (- match->needle_len 1))
            (set gap_score SCORE_GAP_TRAILING)
            (set gap_score SCORE_GAP_INNER))
          (def (j int) 0)
          (while (< j match->haystack_len)
            (if (== (aref match->lower_needle i) (aref match->lower_haystack j))
              (do
                (def (score score_t) SCORE_MIN)
                (if (not i)
                  (set score (+ (* j SCORE_GAP_LEADING) (aref match_bonus j)))
                  j
                  (do
                    (def (a score_t) (+ (aref last_M (- j 1)) (aref match_bonus j)))
                    (def (b score_t) (+ (aref last_D (- j 1)) SCORE_MATCH_CONSECUTIVE))
                    (if (> a b) (set score a) (set score b))))
                (set (aref curr_D j) score)
                (if (> score (+ prev_score gap_score))
                  (set prev_score score)
                  (set prev_score (+ prev_score gap_score)))
                (set (aref curr_M j) prev_score))
              (do
                (set (aref curr_D j) SCORE_MIN)
                (set prev_score (+ prev_score gap_score))
                (set (aref curr_M j) prev_score)))
            ++j))

(function _has_match :static :inline
          [(*needle (const uint8_t)) (*haystack (const uint8_t))] -> int
          (while *needle
            (def (nch uint8_t) *needle++)
            (def ("accept[3]" (const uint8_t)) (array nch (toupper nch) 0))
            (if (! (set haystack (strpbrk haystack accept)))
              (return 0))
            ++haystack)
          (return 1))

(def cnames
  ~((def (*cneedle (const uint8_t)) (janet_string needle.bytes needle.len))
     (def (*chaystack (const uint8_t)) (janet_string haystack.bytes haystack.len))))

(cfunction hasmatch
           ```
           Checks if needle has match in haystack. Returns boolean.
           ```
           [needle:bytes haystack:bytes] -> Janet
           ,;cnames
           (return (janet_wrap_boolean (_has_match cneedle chaystack))))

(cfunction score
           ```
           Computes score for the needle in the haystack. Returns number.
           ```
           [needle:bytes haystack:bytes] -> Janet
           ,;cnames
           (if (or (not *cneedle) (not (_has_match cneedle chaystack)))
             (return (janet_wrap_number SCORE_MIN)))
           (def (match (named-struct match_struct)) nil)
           (setup_match_struct (addr match) cneedle chaystack)

           (def (n int) match.needle_len)
           (def (m int) match.haystack_len)

           (if
             (or (> m MATCH_MAX_LEN) (> n m))
             (return (janet_wrap_number SCORE_MIN))
             (== n m)
             (return (janet_wrap_number SCORE_MAX)))
           (def ("D[2][MATCH_MAX_LEN]" score_t) nil)
           (def ("M[2][MATCH_MAX_LEN]" score_t) nil)
           (def (*last_D score_t) (aref D 0))
           (def (*last_M score_t) (aref M 0))
           (def (*curr_D score_t) (aref D 1))
           (def (*curr_M score_t) (aref M 1))
           (def (i int) 0)
           (def (*tmp score_t) nil)
           (while (< i n)
             (match_row (addr match) i curr_D curr_M last_D last_M)
             (set tmp last_D)
             (set last_D curr_D)
             (set curr_D tmp)
             (set tmp last_M)
             (set last_M curr_M)
             (set curr_M tmp)
             ++i)
           (return (janet_wrap_number (aref last_M (- m 1)))))

(cfunction positions
           ```
           (positions needle haystack)

           Computes positions for the needle in the haystack. Returns array of positions.
           ```
           [needle:bytes haystack:bytes] -> Janet
           ,;cnames
           (def (match (named-struct match_struct)) nil)
           (setup_match_struct (addr match) cneedle chaystack)
           (def (n int) match.needle_len)
           (def (m int) match.haystack_len)
           (def (*array JanetArray) (janet_array n))
           (def (warr Janet) (janet_wrap_array array))
           (if (or (not *cneedle)
                   (not (_has_match cneedle chaystack)))
             (return warr))
           (if
             (or (> m MATCH_MAX_LEN) (> n m))
             (return (janet_wrap_array array))
             (== n m)
             (do
               (def (i int) 0)
               (while (< i n)
                 (janet_array_push array (janet_wrap_number i))
                 (++ i))
               (return warr)))
           (def ("(*D)[MATCH_MAX_LEN]" score_t) nil)
           (def ("(*M)[MATCH_MAX_LEN]" score_t) nil)
           (set M (janet_malloc (* (sizeof score_t) MATCH_MAX_LEN n)))
           (set D (janet_malloc (* (sizeof score_t) MATCH_MAX_LEN n)))
           (def (*last_D score_t) (aref D 0))
           (def (*last_M score_t) (aref M 0))
           (def (*curr_D score_t) (aref D 1))
           (def (*curr_M score_t) (aref M 1))
           (def (i int) 0)
           (while (< i n)
             (set curr_D (addr (aref (aref D i) 0)))
             (set curr_M (addr (aref (aref M i) 0)))
             (match_row (addr match) i curr_D curr_M last_D last_M)
             (set last_D curr_D)
             (set last_M curr_M)
             (++ i))
           (def (match_required int) 0)
           (set i (- n 1))
           (def (j int) (- m 1))
           (while (>= i 0)
             (while (>= j 0)
               (if (and (!= (aref (aref D i) j) SCORE_MIN)
                        (or match_required (== (aref (aref D i) j)
                                               (aref (aref M i) j))))
                 (do
                   (set match_required
                        (and i j (== (aref (aref M i) j)
                                     (+ (aref (aref D (- i 1)) (- j 1))
                                        SCORE_MATCH_CONSECUTIVE))))
                   (janet_putindex warr i (janet_wrap_number j))
                   (-- j)
                   (break)))
               (-- j))
             (-- i))
           (janet_free D)
           (janet_free M)
           (return warr))

(module-entry "fuzzy")
