#! /bin/bash

# Caveats: kills all killable rsyncs
#          don't disturb test timing by putting too much (extra) load on the machine
# Debian: install packages bc, time

TESTDIR=/tmp/monikop-test
DEV=$TESTDIR/dev
MNT=$TESTDIR/mnt
LOG=$TESTDIR/log
MONIKOP_1="../monikop ../test/monikop.config.test.1"
MONIKOP_2="../monikop ../test/monikop.config.test.2"
TEST_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=""

# make_test_drive <name> <size>
function make_test_drive {
    mkdir -p $MNT/$1
    dd if=/dev/zero of=$DEV/$1 bs=1024 count=$2 2> /dev/null
    /sbin/mkfs.ext3 -m 0 -Fq $DEV/$1
    if ! mount $MNT/$1 2> /dev/null; then
        echo "# Can't mount $DEV/$1 to $MNT/$1."
        echo "# Redo from start after adding the following line to your /etc/fstab:"
        echo 
        echo "   $DEV/$1 $MNT/$1 ext3 loop,user,noauto 0 0"
        echo
        return 1
    fi
}

# make_test_file <name> <size> <date>
function make_test_file {
    dd if=/dev/zero of=$1 bs=1024 count=$2 2> /dev/null
    echo ++++++++++++++++++++++++++$RANDOM***$3---$1 >> $1
    touch -t $3 $1
}

# find_and_compare <origin_dir> <origin_dir> ... :: <copy_dir> <copy_dir> ...
function find_and_compare {
    origin_dirs=$1; shift;
    until [[ $1 == "::" ]]; do
        origin_dirs="$origin_dirs $1"; shift;
    done
    shift
    missing=""
    diverging=""
    diverging_mtime=""
    return_value=0
    for i in `find $origin_dirs -type f 2> /dev/null`; do
        found=`find $@ -path "$MNT/*/measuring_data/${i#$MNT/*/data/}" 2> /dev/null`
        if [[ $found == "" ]] ; then
            missing="$missing $i";
        elif ! cmp --quiet $i $found; then
            diverging="$diverging $i"
        elif [[ `stat --printf="%Y" $i` != `stat --printf="%Y" $found` ]]; then
            diverging_mtime="$diverging_mtime $i"
        fi
    done
    if [[ $missing != "" ]]; then
        return_value=1
        echo "MISSING: $missing"
    fi
    if [[ $diverging != "" ]]; then
        return_value=$((return_value + 2))
        echo "DIVERGING: $diverging"
    fi
    if [[ $diverging_mtime != "" ]]; then
        return_value=$((return_value + 4))
        echo "DIVERGING MTIME: $diverging_mtime"
    fi
    return $return_value
}

# run_test <expected_return> <test-command>
function run_test {
    echo "RUNNING $2"
    TEST_COUNT=$(( TEST_COUNT + 1 ))
    $2
    RETURN_VALUE=$?
    if [[ $RETURN_VALUE -ne $1 ]]; then
        FAIL_COUNT=$(( FAIL_COUNT + 1 ))
        FAILED_TESTS="\n$FAILED_TESTS$2($1? $RETURN_VALUE!)"
        echo "$2 should have returned $1 but returned $RETURN_VALUE instead."
    fi
}

umount $MNT/* #2> /dev/null
rm -rf $DEV $MNT $LOG
mkdir -p $DEV $MNT

# Create and mount test drives:
for i in 01 02 03 04; do
    make_test_drive $i 102400
    if [[ $? == 1 ]]; then
        MOUNTING_PROBLEM=1
    fi
done
make_test_drive 05 102400
if [[ $? == 1 ]]; then
    MOUNTING_PROBLEM=1
fi
if [[ $MOUNTING_PROBLEM == 1 ]]; then exit; fi

exit

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
INTERRUPTION_TIME_0=`echo "($T1 + $T2) * 3" | bc`
INTERRUPTION_TIME_1=`echo "($T1 + $T2) * .16" | bc`
INTERRUPTION_TIME_2=`echo "($T1 + $T2) * .82" | bc`
echo $INTERRUPTION_TIME_0
rm -rf $MNT/03/* $MNT/04/*


function test_monikop_simple {
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4}/measuring_data
}

function test_monikop_short {
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_1; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4}/measuring_data
}

function test_monikop_short_kill_rsync_first {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; /usr/bin/killall -KILL rsync; sleep 1; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4,5}/measuring_data
}

function test_monikop_short_umount_sources {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; umount -l $TESTDIR/mnt/0{1,2}; sleep 1; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4,5}/measuring_data
    mount $TESTDIR/mnt/01
    mount $TESTDIR/mnt/02
}

function test_monikop_short_umount_destinations {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_1; umount -l $TESTDIR/mnt/0{3,4,5}; sleep 1; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4,5}/measuring_data
    mount $TESTDIR/mnt/03
    mount $TESTDIR/mnt/04
    mount $TESTDIR/mnt/05
}

function test_monikop_simple_2 {
    $MONIKOP_2 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4,5}/measuring_data
}

function test_monikop_overflow {
# Stuff one of the destinations a bit:
    make_test_file $MNT/03/stuffing 25000 199903250845
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_0; /bin/kill -TERM $!
    find_and_compare $TESTDIR/mnt/0{1,2}/data :: $TESTDIR/mnt/0{3,4}/measuring_data
}

function test_monikop_no_destination {
# We test basically if there is something to kill.
    umount $MNT/{03,04}
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    RETURN=$?
    mount $MNT/03
    mount $MNT/04
    return $RETURN
}

function test_monikop_no_source {
# We test basically if there is something to kill.
    umount $MNT/{01,02}
    $MONIKOP_1 & sleep $INTERRUPTION_TIME_2; /bin/kill -TERM $!
    RETURN=$?
    mount $MNT/01
    mount $MNT/02
    return $RETURN
}

# run_test 0 test_monikop_simple
# 
# mv $MNT/03/measuring_data $MNT/03/backed_up
# mv $MNT/04/measuring_data $MNT/04/backed_up
# rm -rf $LOG
# 
# run_test 0 test_monikop_simple
# 
# rm -rf $MNT/0{3,4}/* $LOG
# 
# run_test 1 test_monikop_short
# run_test 1 test_monikop_short
# run_test 0 test_monikop_simple
# 
# mv $MNT/03/measuring_data $MNT/03/backed_up
# mv $MNT/04/measuring_data $MNT/04/backed_up
# rm -rf $LOG
# 
# run_test 1 test_monikop_short
# run_test 1 test_monikop_short
# run_test 0 test_monikop_simple
# 
# rm -rf $MNT/0{3,4}/* $LOG
# 
# run_test 1 test_monikop_overflow
# 
# rm -rf $MNT/0{3,4}/* $LOG
# 
# run_test 0 test_monikop_no_destination
# run_test 0 test_monikop_no_source
# 
# rm -rf $MNT/0{3,4}/* $LOG
# 
# run_test 1 test_monikop_short_kill_rsync_first
# run_test 0 test_monikop_simple_2
# 
# rm -rf $MNT/0{3,4,5}/* $LOG
# 
# run_test 1 test_monikop_short_umount_sources
# run_test 0 test_monikop_simple_2

rm -rf $MNT/0{3,4,5}/* $LOG

run_test 1 test_monikop_short_umount_destinations
run_test 0 test_monikop_simple_2

rm -rf $MNT/0{3,4,5}/* $LOG


echo "Total number of tests: $TEST_COUNT"
echo "Number of failed tests: $FAIL_COUNT"
echo -e "$FAILED_TESTS"

exit $FAIL_COUNT
