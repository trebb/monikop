#! /bin/bash

for i in monikop-screenshot pokinom-screenshot; do
    xterm -e ./fake-$i.pl & 
    PID=$!
    sleep 5
    import -window fake-$i.pl -crop 475x312+2+2 ../html/$i.png
    kill $PID
done
