(use spork/test)
(use ../gp/datetime)

(start-suite "Core")

(assert (now) "now")

(assert (today) "today")

# initialisation

(def time-stamp-struct
  {:year 1976
   :month 3
   :month-day 23
   :hours 12
   :minutes 0
   :seconds 0})

(assert
  (table? (make-date time-stamp-struct))
  "to date")

(assert
  (table? (make-date-time time-stamp-struct))
  "to time")

(def time-stamp-int 1615478528)

(assert
  (table? (make-date time-stamp-int))
  "to date from int")

(assert
  (table? (make-date-time time-stamp-int))
  "to date from int")

(def time-stamp-string "2021-03-11 16:02:08")

(assert
  (table? (make-date time-stamp-string))
  "to date from str")

(def time-stamp-slash-string "2021/03/11 16:02:08")

(assert
  (table? (make-date-time time-stamp-slash-string))
  "to date from slash str 1")

(assert
  (deep= (make-date-time time-stamp-slash-string)
         @{:dst false :seconds 8 :minutes 2 :hours 16 :week-day 4
           :month 2 :month-day 10 :year 2021 :year-day 69})
  "to date from slash str 2")

(def time-stamp-T-string "2021-03-11T16:02:08")

(assert
  (table? (make-date-time time-stamp-T-string))
  "to date from slash str 3")

(assert
  (deep= (make-date-time time-stamp-T-string)
         @{:dst false :seconds 8 :minutes 2 :hours 16 :week-day 4
           :month 2 :month-day 10 :year 2021 :year-day 69})
  "to date from slash str 4")

(def time-stamp-wrong "2021-13-11 16:02:08")

(assert
  (= ((make-date time-stamp-wrong) :month)
     0)
  "to date from wrong str")

(def minutes-string "2021-03-11 16:02")

(assert
  (= ((make-date-time minutes-string) :seconds)
     0)
  "to date time from string")

(def hours-string "2021-03-11 16")

(assert
  (table? (make-date-time hours-string))
  "to date time from string")

(def date-string "2021-03-11")

(assert
  (table? (make-date date-string))
  "to date from str")

(def month-string "2021-03")

(assert
  (table? (make-date month-string))
  "to date from str")

(def year-string "2021")

(assert
  (table? (make-date year-string))
  "to date from str")

# formating

(assert
  (=
    (:format (make-date time-stamp-struct))
    "1976-04-24")
  "format to date")

(assert
  (=
    (:format (make-date-time time-stamp-struct))
    "1976-04-24 12:00:00")
  "format to date")

(assert
  (=
    (:format (make-date time-stamp-int))
    "2021-03-11")
  "format to date from int")

(assert
  (=
    (:format (make-date-time time-stamp-int))
    "2021-03-11 16:02:08")
  "format to date from int")

(assert
  (=
    (:format (make-date time-stamp-string))
    "2021-03-11")
  "format to date from str")

(assert
  (=
    (:format (make-date-time time-stamp-string))
    "2021-03-11 16:02:08")
  "format to datetime from string")

(assert
  (=
    (:http-format (make-date-time time-stamp-struct))
    "Sat, 24 Apr 1976 12:00:00 GMT")
  "format to date time for HTTP date")

# epoch

(assert
  (=
    (:epoch (make-date time-stamp-string))
    1615420800)
  "date epoch")

(assert
  (=
    (:epoch (make-date-time time-stamp-string))
    time-stamp-int)
  "date time mktime")

# interval

(assert
  (table? (make-interval 10))
  "make interval")

(assert
  (=
    ((make-interval {:years 1
                     :days 1
                     :hours 1
                     :minutes 1
                     :seconds 1}) :duration)
    31626061)
  "make interval duration")

(assert
  (=
    ((make-interval {:days 1}) :duration)
    86400)
  "untis interval")

(assert
  (=
    ((make-interval {:start 10 :end 20}) :duration)
    10)
  "start end interval")

(assert
  (=
    ((make-interval "1h 1 minute 1 sec") :duration)
    3661)
  "string interval")

# interval format

(assert
  (= (:format (make-interval "1h 1 minute 1 sec"))
     "1:01:01")
  "interval format")

# interval computing

(assert
  (compare> (make-interval {:start 0 :end 60})
            (make-interval {:start 0 :end 20}))
  "compare intervals")

(assert
  (deep= (:add (make-interval {:start 0 :end 20})
               (make-interval {:start 0 :end 20}))
         (make-interval 40))
  "add interval")

(assert
  (deep= (:sub (make-interval {:start 0 :end 60})
               (make-interval {:start 0 :end 20}))
         (make-interval 40))
  "substract interval")

# calendar

(assert
  (table?
    (make-calendar time-stamp-struct))
  "make calendar")

(assert (= ((:later (make-calendar time-stamp-struct)
                    {:days 1}) :month-day)
           24)
        "later")

(assert (= ((:sooner (make-calendar time-stamp-struct)
                     {:days 1}) :month-day)
           22)
        "sooner")

# calculations

(assert
  (:before? (make-calendar time-stamp-struct)
            (:later (make-calendar time-stamp-struct)
                    {:days 1}))
  "calendar before")

(assert
  (:after? (make-calendar time-stamp-struct)
           (:sooner (make-calendar time-stamp-struct)
                    {:days 1}))
  "calendar after")

(assert
  (compare> (make-calendar time-stamp-struct)
            (:sooner (make-calendar time-stamp-struct)
                     {:days 1}))
  "calendar compare")

(assert
  (compare< (make-calendar time-stamp-struct)
            (:later (make-calendar time-stamp-struct)
                    {:days 1}))
  "calendar compare")

# period

(assert
  (table? (make-period time-stamp-struct {:days 1}))
  "period table")

(assert
  (= (:start (make-period time-stamp-struct {:days 1}))
     199195200)
  "period start")

(assert
  (= (:end (make-period time-stamp-struct {:days 1}))
     199281600)
  "period end")

(assert
  (:contains? (make-period time-stamp-struct {:days 1})
              (make-date-time time-stamp-struct))
  "period contains")

(assert-not
  (:contains? (make-period time-stamp-struct {:days 1})
              (:later (make-calendar time-stamp-struct) {:days 2}))
  "period does not contain")

(assert
  (= ((:later (make-period time-stamp-struct {:days 1}) {:days 1})
       :month-day)
     25)
  "later period")

(assert
  (:after?
    (make-period time-stamp-struct {:days 1})
    (:later (make-calendar time-stamp-struct)
            {:days 2}))
  "after period")

# period helpers

(assert (= 60 (minutes 1))
        "minutes")

(assert (= (minutes 60) (hours 1))
        "hours")

(assert (= (hours 24) (days 1))
        "days")

(assert (= (days 7) (weeks 1))
        "weeks")

(assert (= (days 365) (years 1))
        "years")

(assert (= (:str-week-day (make-date time-stamp-struct))
           "Sat"))

(assert (= (:str-week-day (make-date time-stamp-struct) :long)
           "Saturday"))

(assert (= (:str-week-day (make-date-time time-stamp-struct))
           "Sat"))

(assert (= (:str-week-day (make-date-time time-stamp-struct) :long)
           "Saturday"))

(assert (= (:str-month (make-date time-stamp-struct))
           "Apr"))

(assert (= (:str-month (make-date time-stamp-struct) :long)
           "April"))

(assert (= (:str-month (make-date-time time-stamp-struct))
           "Apr"))

(assert (= (:str-month (make-date-time time-stamp-struct) :long)
           "April"))

(assert (= (:in-years (make-interval {:days 365})) 1) "in-years")

(assert (= (:in-days (make-interval {:hours 24})) 1) "in-days")

(assert (= (:in-hours (make-interval {:days 1})) 24) "in-hours")

(assert (= (:in-minutes (make-interval {:hours 1})) 60) "in-minutes")

# DST on Alpine?
# (assert (= 14 ((:local (make-date-time time-stamp-struct)) :hours))
#        "local date")

# (assert ((tracev (:local (make-date-time time-stamp-struct))) :dst))

(assert-docs "../gp/datetime")
(end-suite)

(start-suite "Utils")

(def tepoch 1615503728)
(assert (= (format-date-time tepoch)
           "2021-03-11 23:02:08")
        "format-date-time")

(assert (= (format-date-time tepoch true)
           "2021-03-12 0:02:08")
        "local format-date-time")

(with-dyns [:local-time true]
  (assert (= (format-date-time tepoch)
             "2021-03-12 0:02:08")
          "local dyn format-date-time"))

(assert (= (http-format-date-time tepoch)
           "Thu, 11 Mar 2021 23:02:08 GMT")
        "format-date-time")

(assert (= (format-date tepoch)
           "2021-03-11")
        "format-date")

(assert (= (format-time tepoch)
           "23:02")
        "format-time")

(assert (= (format-time tepoch true)
           "0:02")
        "local format-time")

(assert (= (format-interval 1_000_002)
           "277:46:42")
        "format-interval")

(assert (= (format-interval "0:00:00")
           "0:00:00")
        "format-interval 1")

(assert (= (format-today) (:format (today)))
        "fomat-today")

(assert (= (format-now) (:format (now)))
        "fomat-now")

(assert (:after? (make-calendar (today)) (days-ago 1))
        "days-ago")

(assert (:after? (make-calendar (today)) (yesterday))
        "yesterday")

(assert (:after? (make-calendar (yesterday)) (days-ago 2))
        "days-ago 2")

(assert (:after? (make-calendar (days-ago 6)) (weeks-ago 1))
        "weeks-ago")

(def date (make-date "2021-09-27"))

(assert (= (:epoch (days-after 2 date))
           (:epoch (make-date "2021-09-29")))
        "days-after")

(assert (= (:epoch (start-of-week 2 date))
           (:epoch (make-date "2021-10-10")))
        "start of week")

(assert (= (:epoch (start-of-week -1 date))
           (:epoch (make-date "2021-09-19")))
        "start of week")

(assert (= (:epoch (current-week-start date))
           (:epoch (make-date "2021-09-26")))
        "current-week-start")

(assert (= (:epoch (last-week-start date))
           (:epoch (make-date "2021-09-19")))
        "last-week-start")

(assert (= (:epoch (current-month-start date))
           (:epoch (make-date "2021-09-01")))
        "current-month-start")

(assert (= (:epoch (start-of-month 0 date))
           (:epoch (make-date "2021-09-01")))
        "start-of-month 0")

(assert (= (:epoch (start-of-month -1 date))
           (:epoch (make-date "2021-08-01")))
        "start-of-month -1")

(assert (= (:epoch (last-month-start date))
           (:epoch (make-date "2021-08-01")))
        "last-month-start")

(assert (= (:epoch (start-of-month 1 date))
           (:epoch (make-date "2021-10-01")))
        "start-of-month 1")

(assert (= (:epoch (start-of-month 2 date))
           (:epoch (make-date "2021-11-01")))
        "start-of-month 2")

(assert (= (:epoch (start-of-month 12 date))
           (:epoch (make-date "2022-09-01")))
        "start-of-month 12")

(assert (= (:epoch (start-of-month 3 date))
           (:epoch (make-date "2021-12-01")))
        "start-of-month 3")

(assert (= (:epoch (start-of-month -2 date))
           (:epoch (make-date "2021-07-01")))
        "start-of-month -2")

(assert (= (:epoch (start-of-month -12 date))
           (:epoch (make-date "2020-09-01")))
        "start-of-month -12")

(assert (= (:epoch (start-of-year 0 date))
           (:epoch (make-date "2021-01-01")))
        "start-of-year 0")

(assert (= (:epoch (current-year-start date))
           (:epoch (make-date "2021-01-01")))
        "current-year-start")

(assert (= (:epoch (start-of-year -1 date))
           (:epoch (make-date "2020-01-01")))
        "start-of-year 1")

(assert (= (:epoch (start-of-year 1 date))
           (:epoch (make-date "2022-01-01")))
        "start-of-year -1")

(def n (now))
(def cn (make-calendar n))

(assert (= (human n) "now") "now")

(assert (= (human (:sooner cn {:minutes 1})) "now") "now almost")

(assert (= (human (:sooner cn {:minutes 7})) "about now") "about now")

(assert
  (= (human (:sooner cn {:hours 5})) "today") "today")

(assert
  (= (human (:sooner cn {:hours 23})) "yesterday") "yesterday")

(assert (= (human (:sooner cn {:days 8})) "2 weeks ago")
        "2 weeks ago")

(assert (= (human (:sooner cn {:days 15})) "3 weeks ago")
        "3 weeks ago")

(assert (= (human (:sooner cn {:days 32})) "2 months ago")
        "2 months ago")

(assert (= (human (:sooner cn {:days 365})) "last year")
        "last year")

(def dtn (make-calendar "2021-11-15 14:13:15"))

(assert
  (= (human (:sooner dtn {:hours 5}) dtn) "today") "today")

(assert (= (human (:sooner dtn {:hours 47}) dtn) "Saturday")
        "2 days ago")

(assert (= (human (:sooner dtn {:hours 71}) dtn) "Friday")
        "3 days ago")

(assert (= (human (:sooner dtn {:hours 95}) dtn) "Thursday")
        "4 days ago")


(end-suite)
