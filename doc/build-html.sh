#! /usr/bin/env bash
set -ev

VERSION=$(git describe --tags | cut -d "-" -f 1)
rm -rf ../doc-tmp
cp -R ../doc ../doc-tmp

(
    cd ../doc-tmp
    echo -e ",s/_PUT_VERSION_HERE_/$VERSION/g\nwq" | ed -s download.muse
    emacs --script build-html.el
)
