(use spork/test)
(import gp/environment/app)

(start-suite "Sending email")

(defn after
  "The value that follows `flag` in `command`."
  [command flag]
  (get command (+ 1 (index-of flag command))))

(def from "Registry <registry@example.org>")

# Nothing here sends a letter: the command is a value, so what curl would be
# told can be read without a mail server to tell it to.
(let [command (app/send-email/command "smtp://smtp.example.org:587" from "secret"
                                      nil "student@example.com" "letter.mail")]
  (assert (= "curl" (first command)) "the command is curl")
  (assert (= "registry@example.org:secret" (after command "--user"))
          "without a login, the address in `me` signs in")
  (assert (= "registry@example.org" (after command "--mail-from"))
          "the envelope sender is the address between the angle brackets")
  (assert (= "student@example.com" (after command "--mail-rcpt")) "the recipient")
  (assert (= "letter.mail" (after command "--upload-file")) "the letter")
  (assert (= "smtp://smtp.example.org:587" (after command "--url")) "the server")
  (assert (index-of "--ssl-reqd" command) "TLS is required")
  (assert (index-of "-sS" command) "no progress meter, but a failure is still said")
  (assert (= "60" (after command "--max-time")) "a silent server cannot hold the caller"))

(let [command (app/send-email/command "smtp://smtp.example.org:587" from "secret"
                                      "reg01" "student@example.com" "letter.mail")]
  (assert (= "reg01:secret" (after command "--user"))
          "a login of its own signs in instead of the address")
  (assert (= "registry@example.org" (after command "--mail-from"))
          "and the letter is still sent as the address"))

(assert (function? (app/make-send-email "smtp://h:587" from "secret"))
        "make-send-email still takes three arguments")
(assert (function? (app/make-send-email "smtp://h:587" from "secret" "reg01"))
        "and a fourth, the login")

(end-suite)
