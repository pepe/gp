(use spork/misc spork/json ./navigation ./schema)

(defdyn *separator* "Separator for the csv")

(defn splitter
  "Creates function that will split its argument with `separator`"
  [separator]
  (fn [x] (string/split separator x)))

(defn slurp-trim
  "Slurps file and trims its ws"
  [path]
  (-> path slurp string/trim))

(defn jdn->csv-record
  "Joins parts with the *separator* and returns it as a string"
  [parts]
  (string/join parts (dyn *separator* ",")))

(defn csv-record->jdn
  "Splits `csv-record` string into an array of fields"
  [csv-record]
  ((=> string/trim (splitter (dyn *separator* ","))) csv-record))

(defn json-file->jdn
  "Slurps json file with one object and convert it to native janet"
  [path]
  ((=> slurp-trim decode) path))

(defn jsons-file->jdn
  "Slurps json file with object separated by nl and convert it to native janet"
  [path]
  ((=> slurp-trim
       (splitter "\n")
       (>fn decode))
    path))
