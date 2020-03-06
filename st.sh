tokei -s lines -f -t=D -e tests -e*_test.d
dscanner --styleCheck \
    | grep -v Public.declaration.*is.undocumented \
    | grep -v appwindow.d.*Variable.[ab].is.never.modified
git status
