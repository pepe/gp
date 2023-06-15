(use spork/cjanet)

(@ define TB_IMPL)

(include <stdio.h>)
(include <janet.h>)
(include `"../src/termbox2.h"`)

(cfunction
  init :static
  "Initializes TUI"
  [] -> Janet
  (tb_init)
  (return (janet_wrap_nil)))

(cfunction
  shutdown :static
  "Shutdowns TUI"
  [] -> Janet
  (tb_shutdown)
  (return (janet_wrap_nil)))

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
  set-cursor :static
  "Sets the cursor to `x` `y`"
  [x:int y:int] -> Janet
  (tb_set_cursor x y)
  (return (janet_wrap_nil)))

(cfunction
  hide-cursor :static
  "Hides cursor"
  [] -> Janet
  (tb_hide_cursor)
  (return (janet_wrap_nil)))

(cfunction
  set-cell :static
  "Sets the cell on `x` `y` to ch with fg and bg."
  [x:int y:int ch:int fg:int bg:int] -> Janet
  (tb_set_cell x y ch fg bg)
  (return (janet_wrap_nil)))

(cfunction
  present :static
  "Presents TUI"
  [] -> Janet
  (tb_present)
  (return (janet_wrap_nil)))

(cfunction
  print :static
  "Prints to TUI"
  [x:int y:int fg:int bg:int str:string] -> Janet
  (tb_print x y fg bg str)
  (return (janet_wrap_nil)))

(module-entry "tui")
