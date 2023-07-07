(use spork/misc spork/cjanet)

(@ define _BSD_SOURCE)
(@ define _DEFAULT_SOURCE)
(@ define TB_IMPL)
(@ define TB_OPT_TRUECOLOR)
(include `"../src/termbox2.h"`)
(@ undef TB_IMPL)

(include <stdio.h>)
(include <janet.h>)

(defmacro defs [pref & keys]
  (seq [k :in keys
        :let [ks (cond->> k
                          pref (string pref "-"))
              ds (string/replace-all "-" " " ks)
              ts (->> ks
                      (string/replace-all "-" "_")
                      string/ascii-upper
                      (string "TB_")
                      symbol)]]
    ~(cdef ,ks ,ds (janet_wrap_integer ,ts))))

(defs nil
  default black red green yellow blue magenta cyan white
  bold underline reverse
  ok err)
(defs :key
  ctrl-tilde ctrl-2 ctrl-a ctrl-b ctrl-c ctrl-d ctrl-e ctrl-f ctrl-g backspace ctrl-h tab ctrl-i ctrl-j ctrl-k ctrl-l enter ctrl-m ctrl-n ctrl-o ctrl-p ctrl-q ctrl-r ctrl-s ctrl-t ctrl-u ctrl-v ctrl-w ctrl-x ctrl-y ctrl-z esc ctrl-lsq-bracket ctrl-3 ctrl-4 ctrl-backslash ctrl-5 ctrl-rsq-bracket ctrl-6 ctrl-7 ctrl-slash ctrl-underscore space backspace2 ctrl-8 f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 insert delete home end pgup pgdn arrow-up arrow-down arrow-left arrow-right back-tab mouse-left mouse-right mouse-middle mouse-release mouse-wheel-up mouse-wheel-down)
(defs :cap
  f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12 insert delete home end
  pgup pgdn arrow-up arrow-down arrow-left arrow-right back-tab -count-keys
  enter-ca exit-ca show-cursor hide-cursor clear-screen sgr0 underline bold
  blink italic reverse enter-keypad exit-keypad -count)
(defs :mod alt motion ctrl shift)
(defs :event key resize mouse)
(defs :input current esc alt mouse)
(defs :output current normal 256 216 grayscale truecolor)
(defs :err
  need-more init-already init-open mem no-event no-term not-init out-of-bounds
  read resize-ioctl resize-pipe resize-sigaction poll tcgetattr tcsetattr
  unsupported-term resize-write resize-poll resize-read resize-sscanf
  cap-collision select resize-select)

(function eventt_get [*p:void key:Janet *out:Janet] -> int)

(typedef tb_event (named-struct tb_event))

(declare
  (eventt JanetAbstractType) :static :const
  (array "term-event" NULL NULL eventt_get JANET_ATEND_GET))

(cfunction
  init-event :static
  "Initializes new event"
  [] -> Janet
  (def (*event (named-struct tb_event)) (janet_abstract &eventt (sizeof '"struct tb_event")))
  (return (janet_wrap_abstract event)))

(cfunction
  poll :static
  "Polls for the new event"
  [event:&eventt] -> Janet
  (def (*sevent (named-struct tb_event)) '"(struct tb_event*) event")
  (return (janet_wrap_integer (tb_poll_event sevent))))


(defmacro efunctions
  "Generates functions working on event"
  [& fns]
  (array/push
    (seq [name :in fns]
      ~(cfunction
         ,name :static
         ,(string "Returns the `" name "` of the `event`")
         [event:&eventt] -> Janet
         (def (*sevent (named-struct tb_event)) '"(struct tb_event*) event")
         (return (janet_wrap_integer (cast int32_t (-> sevent ,name))))))
    ~(declare (methods (array JanetMethod)) :static :const
              (array ,;(seq [f :in fns] (array (string f) (symbol '_generated_cfunction_ f)))
                     (array NULL NULL)))))

(efunctions :type :mod :key :w :h :x :y :ch)

(function
  eventt_get [*p:void key:Janet *out:Janet] -> int
  (def (*event tb_event) (cast tb_event* p))
  (if (janet_checktype key JANET_KEYWORD)
    (return (janet_getmethod (janet_unwrap_keyword key) methods out))))

(cfunction
  init :static
  "Initializes TUI"
  [] -> Janet
  (return (janet_wrap_integer (tb_init))))

(cfunction
  shutdown :static
  "Shutdowns TUI"
  [] -> Janet
  (return (janet_wrap_integer (tb_shutdown))))

(cfunction
  width :static
  "Returns window width"
  [] -> Janet
  (return (janet_wrap_number (tb_width))))

(cfunction
  height :static
  "Returns window height"
  [] -> Janet
  (return (janet_wrap_number (tb_height))))

(cfunction
  present :static
  "Presents TUI"
  [] -> Janet
  (return (janet_wrap_integer (tb_present))))

(cfunction
  clear :static
  "Clears TUI"
  [] -> Janet
  (return (janet_wrap_integer (tb_clear))))

(cfunction
  set-cursor :static
  "Sets the cursor to `x` `y`"
  [x:int y:int] -> Janet
  (return (janet_wrap_integer (tb_set_cursor x y))))

(cfunction
  hide-cursor :static
  "Hides cursor"
  [] -> Janet
  (return (janet_wrap_integer (tb_hide_cursor))))

(cfunction
  set-cell :static
  "Sets the cell on `x` `y` to ch with fg and bg."
  [x:int y:int ch:int fg:int bg:int] -> Janet
  (tb_set_cell x y ch fg bg)
  (return (janet_wrap_nil)))

(cfunction
  print :static
  "Prints to TUI"
  [x:int y:int fg:int bg:int str:string] -> Janet
  (tb_print x y fg bg str)
  (return (janet_wrap_nil)))

(cfunction
  set-output-mode :static
  "Sets the termbox output mode"
  [mode:int] -> Janet
  (return (janet_wrap_integer (tb_set_output_mode mode))))

(module-entry "term")
