#!/bin/bash 

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# USAGE:
#
#     steps/compute_cmvn_stats.sh \
#         data_dir/train_dir \
#         experiment_dir/make_mfcc_log/train_dir \
#         mfcc_dir;

# INPUT:
#
#    /data/{test,train}/
#        spk2utt
#        feats.scp

# OUTPUT:
#
#   /data/{test,train}/
#       cmvn.scp
# 
#   /mfcc/
#       cmvn_{test,train}.{scp,ark}
# 
#   nb - the cmvn.scp is a list of paths to the cmvn_{train,test}.ark files


# Compute cepstral mean and variance statistics per speaker.  
# We do this in just one job; it's fast.
# This script takes no options.
#
# Note: there is no option to do CMVN per utterance.  The idea is
# that if you did it per utterance it would not make sense to do
# per-speaker fMLLR on top of that (since you'd be doing fMLLR on
# top of different offsets).  Therefore what would be the use
# of the speaker information?  In this case you should probably
# make the speaker-ids identical to the utterance-ids.  The
# speaker information does not have to correspond to actual
# speakers, it's just the level you want to adapt at.

# get variables before we run the script
( set -o posix ; set ) >variables.before

fake=false   # If specified, can generate fake/dummy CMVN stats (that won't normalize)
fake_dims=   # as the "fake" option, but you can generate "fake" stats only for certain
             # dimensions.
two_channel=false

if [ "$1" == "--fake" ]; then
    fake=true
    shift
fi
if [ "$1" == "--fake-dims" ]; then
    fake_dims=$2
    shift
    shift
fi
if [ "$1" == "--two-channel" ]; then
    two_channel=true
    shift
fi

if [ $# != 3 ]; then
    echo "Usage: $0 [options] <data-dir> <log-dir> <path-to-cmvn-dir>";
    echo "e.g.: $0 data/train exp/make_mfcc/train mfcc"
    echo "Options:"
    echo " --fake          gives you fake cmvn stats that do no normalization."
    echo " --two-channel   is for two-channel telephone data, there must be no segments "
    echo "                 file and reco2file_and_channel must be present.  It will take"
    echo "                 only frames that are louder than the other channel."
    echo " --fake-dims <n1:n2>  Generate stats that won't cause normalization for these"
    echo "                  dimensions (e.g. 13:14:15)"
    exit 1;
fi

if [ -f path.sh ]; then . ./path.sh; fi

data_dir=$1
log_dir=$2
cmvn_dir=$3
verbose=false

if [ $verbose = true ]; then
    printf "\n###\n## BEGIN PARAMETERS FOR $0\n#\n\n"
    # get variables after we set them
    ( set -o posix ; set ) >variables.after
    # find and show the difference
    diff variables.before variables.after
    printf "\n#\n## END PARAMETERS FOR $0\n###\n\n"
fi

# remove files
rm -f variables.before variables.after

# make $cmvn_dir an absolute pathname.
cmvndir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $cmvn_dir ${PWD}`

# use "name" as part of name of the archive.
name=`basename $data_dir`

mkdir -p $cmvn_dir || exit 1;
mkdir -p $log_dir || exit 1;


required="$data_dir/feats.scp $data_dir/spk2utt"

for f in $required; do
    if [ ! -f $f ]; then
        echo "make_cmvn.sh: no such file $f"
        exit 1;
    fi
done

if $fake; then
    dim=`feat-to-dim scp:$data_dir/feats.scp -`
    ! cat $data_dir/spk2utt | awk -v dim=$dim \
        '{print $1, "["; for (n=0; n < dim; n++) { printf("0 "); } print "1";
        for (n=0; n < dim; n++) { printf("1 "); } print "0 ]";}' | \
            copy-matrix ark:- \
            ark,scp:$cmvn_dir/cmvn_$name.ark,$cmvn_dir/cmvn_$name.scp && \
            echo "Error creating fake CMVN stats" && exit 1;

elif $two_channel; then
    ! compute-cmvn-stats-two-channel $data_dir/reco2file_and_channel \
        scp:$data_dir/feats.scp \
        ark,scp:$cmvn_dir/cmvn_$name.ark,$cmvn_dir/cmvn_$name.scp 2> \
        $log_dir/cmvn_$name.log && \
        echo "Error computing CMVN stats (using two-channel method)" && exit 1;

elif [ ! -z "$fake_dims" ]; then
    ! compute-cmvn-stats --spk2utt=ark:$data_dir/spk2utt \
        scp:$data_dir/feats.scp ark:- | modify-cmvn-stats "$fake_dims" \
        ark:- ark,scp:$cmvn_dir/cmvn_$name.ark,$cmvn_dir/cmvn_$name.scp && \
        echo "Error computing (partially fake) CMVN stats" && exit 1;

else
    ! compute-cmvn-stats \
        --spk2utt=ark:$data_dir/spk2utt \
        scp:$data_dir/feats.scp \
        ark,scp:$cmvn_dir/cmvn_$name.ark,$cmvn_dir/cmvn_$name.scp 2> \
        $log_dir/cmvn_$name.log && echo "Error computing CMVN stats" && exit 1;
fi

cp $cmvn_dir/cmvn_$name.scp $data_dir/cmvn.scp || exit 1;

nc=`cat $data_dir/cmvn.scp | wc -l` 
nu=`cat $data_dir/spk2utt | wc -l` 
if [ $nc -ne $nu ]; then
    echo "$0: warning: not all of the speakers got cmvn stats ($nc != $nu);"
    [ $nc -eq 0 ] && exit 1;
fi

printf "\nSucceeded creating CMVN stats for ${name}\n\n"
