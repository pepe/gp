(use spork/cjanet)

(include <janet.h>)
(include `"../termbox2.h"`)

(cfunction
  init :static
  "Initializes TUI"
  [] -> Janet
  (tb_init)
  (return (janet_wrap_nil)))

(module-entry "tui")
