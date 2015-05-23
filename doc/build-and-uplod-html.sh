#! /usr/bin/env bash
# Make and upload Monikop's web page.
# (The screenshots need to be made manually.)

set -ve

GIT_VERSION=$(git describe --tags | cut -d "-" -f 1)
NEWS_VERSION=$(grep -om1 -Ee "v[0-9]+\.[0-9]+\.[0-9]" ../NEWS)
MONIKOP_VERSION=$(grep -om1 -Ee "v[0-9]+\.[0-9]+\.[0-9]" ../monikop)
POKINOM_VERSION=$(grep -om1 -Ee "v[0-9]+\.[0-9]+\.[0-9]" ../pokinom)

echo $GIT_VERSION
echo $NEWS_VERSION
[ $NEWS_VERSION == $GIT_VERSION ]
echo $MONIKOP_VERSION
[ $MONIKOP_VERSION == $GIT_VERSION ]
echo $POKINOM_VERSION
[ $POKINOM_VERSION == $GIT_VERSION ]

./build-html.sh

(
    cd ../html
    git init
    git add ./
    git commit -a -m "gh-pages pseudo commit"
    git push git@github.com:trebb/monikop.git +master:gh-pages
)
