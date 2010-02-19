#! /bin/bash -e
# Make and upload Monikop's web page.
# (The screenshots need to be made manually.)

./build-html.el

(
    cd ../html
    rsync -aP ./ trebb@shell.berlios.de:/home/groups/monikop/htdocs/
    )