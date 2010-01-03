#! /bin/bash

TESTDIR=/tmp/monikop-test
DEV=$TESTDIR/dev
MNT=$TESTDIR/mnt

umount $MNT/* 2> /dev/null
rm -rf $dev $mnt
mkdir -p $DEV
for i in 01 02 03 04; do
    mkdir -p $MNT/$i
    dd if=/dev/zero of=$DEV/$i bs=1024 count=102400 2> /dev/null
    /sbin/mkfs.ext3 -Fq $DEV/$i
    if ! mount $MNT/$i 2> /dev/null; then
        echo "# Can't mount $DEV/$i to $MNT/$i."
        echo "# Redo from start after adding the following line to your /etc/fstab:"
        echo 
        echo "   $DEV/$i $MNT/$i ext3 loop,user,noauto 0 0"
        echo
        MOUNTING_PROBLEM=1
    fi
done
if [[ $MOUNTING_PROBLEM == 1 ]]; then exit; fi

# make_test_file <name> <size> <date>
function make_test_file {
    dd if=/dev/zero of=$1 bs=1024 count=$2 2> /dev/null
    echo ++++++++++++++++++++++++++$RANDOM***$3---$1 >> $1
    touch -t $3 $1
}

# find_and_compare <origin_dir> <copy_dir> <copy_dir> ...
function find_and_compare {
    origin_dir=shift
    for i in `find $origin_dir -type f 2> /dev/null`; do
        for j in $@; do
            find $j -wholename $i -exec cmp \{\} $i \;
        done
    done
}


# Prepare data sources:
mkdir -p $MNT/01/data/d1/d2
mkdir -p $MNT/02/data/d1/d2
for i in f1 f2 f3; do
    make_test_file $MNT/01/data/$i 25000 200703250845.33
done
for i in f10 f11 f12; do
    make_test_file $MNT/02/data/$i 25000 200703250845.33
done
for i in f4 f5 f6; do
    make_test_file $MNT/01/data/d1/$i 2000 200703250845.33
    make_test_file $MNT/01/data/d1/d2/$i 2000 200703250845.33
done
for i in f7 f8 f9; do
    make_test_file $MNT/02/data/d1/$i 2000 200703250845.33
    make_test_file $MNT/02/data/d1/d2/$i 2000 200703250845.33
done


# Check how fast we are:

T1=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/01/data/ $MNT/03/ 2>&1 &`
T2=`/usr/bin/time --format="%e" rsync --recursive --times $MNT/02/data/ $MNT/04/ 2>&1 &`
INTERRUPTION_TIME_1=`echo "($T1 + $T2) * .08" | bc`
INTERRUPTION_TIME_2=`echo "($T1 + $T2) * .41" | bc`
rm -rf $MNT/03/* $MNT/04/*

# Stuff one of the destinations a bit:
make_test_file $MNT/03/stuffing 25000 199903250845


## like this:
#monikop & sleep $INTERRUPTION_TIME_1; kill $!
#monikop & sleep $INTERRUPTION_TIME_1; killall rsync (make sure we kill only our rsyncs)
#
#
#if cmp --quiet file1 file2; then echo ... differ; fi
#
