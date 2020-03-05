tokei -s lines -f -t=D -e tests
dscanner --styleCheck \
    | grep -v Public.declaration.*is.undocumented
git status
