(import spork/cjanet :prefix "" :fresh true)
(use ./fzycode)

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

(defn assign-ref [i v]
  ~(literal ,(string "[" i "] = " v)))

(def punctuation
  (seq [[c s] :in [["/" "SCORE_MATCH_SLASH"]
                   ["-" "SCORE_MATCH_WORD"]
                   ["_" "SCORE_MATCH_WORD"]
                   [" " "SCORE_MATCH_WORD"]
                   ["." "SCORE_MATCH_DOT"]]]
    (assign-ref c s)))

(defn assign-lower [v]
  (seq [c :range [97 123]] (assign-ref c v)))

(defn assign-upper [v]
  (seq [c :range [65 91]] (assign-ref c v)))

(defn assign-digit [v]
  (seq [c :range [48 58]] (assign-ref c v)))

(typedef score_t double)

(declare
  (bonuss_index (array (const size_t) 256))
  @[,;(assign-digit 1)
    ,;(assign-lower 1)
    ,;(assign-upper 2)])

(declare
  (bonuss_states (array (const size_t) (literal "256][3")))
  @[@[0]
    @[,;punctuation]
    @[,;punctuation
      ,;(assign-lower "SCORE_MATCH_CAPITAL")]])

((named-struct
   match_struct
   needle_len int
   haystack_len int
   "lower_needle[MATCH_MAX_LEN]" uint8_t
   "lower_haystack[MATCH_MAX_LEN]" uint8_t
   "match_bonus[MATCH_MAX_LEN]" score_t))
