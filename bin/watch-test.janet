(use /gp/utils)

(filewatch '(thru (* (+ ".janet" ".cjanet" ".temple") -1)) [jpm "test"])
