tokei -s lines -f -t=D -etests
dscanner --styleCheck \
    | grep -v Public.declaration.*is.undocumented \
    | grep -v appwindow.d.*Variable.[ab].is.never.modified \
    | grep -v model.d.*Variable.in[DC].*tion.is.never.modified
git status
