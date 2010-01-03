#! /bin/bash

TESTDIR=/tmp/monikop-test
DEV=$TESTDIR/dev
MNT=$TESTDIR/mnt

umount $MNT/* 2> /dev/null
rm -rf $dev $mnt
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

function make_test_file {
    dd if=/dev/zero of=$1 bs=1024 count=$2 2> /dev/null
    echo ++++++++++++++++++++++++++$RANDOM***$3---$1 >> $1
    touch -t $3 $1
}

for i in f1 f2 f3; do
    make_test_file $MNT/01/$i 25000 200703250845.33
done
exit
mkdir -p $MNT/01/d1/d2
for i in f4 f5 f6; do
    make_test_file $MNT/01/d1/$i 2000 200703250845.33
    make_test_file $MNT/01/d1/d2/$i 2000 200703250845.33
done
mkdir -p $MNT/02/d1/d2
for i in f7 f8 f9; do
    make_test_file $MNT/02/d1/$i 2000 200703250845.33
    make_test_file $MNT/02/d1/d2/$i 2000 200703250845.33
done
