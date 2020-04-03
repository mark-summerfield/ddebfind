tokei -s lines -f -t=D -etests -estemmer.d
dscanner --styleCheck \
    | grep -v Public.declaration.*is.undocumented \
    | grep -v appwindow.d.*Variable.[ab].is.never.modified \
    | grep -v appwindow.d.*Variable.kv.is.never.modified \
    | grep -v appwindow.d.*metrics.is.never.modified \
    | grep -v helpform.d.*Variable.kv.is.never.modified \
    | grep -v model.d.*Variable.*Task.is.never.modified \
    | grep -v model.d.*Variable.*Tuple.is.never.modified \
    | grep -v modelutil.d.*Variable.in[DC].*tion.is.never.modified \
    | grep -v model_test.d.*Variable.timer.is.never.modified
git status
