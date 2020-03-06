tokei -s lines -f -t=D -etests
dscanner --styleCheck \
    | grep -v Public.declaration.*is.undocumented \
    | grep -v appwindow.d.*Variable.[ab].is.never.modified
git status
