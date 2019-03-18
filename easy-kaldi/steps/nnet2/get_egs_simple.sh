#!/bin/bash

# Copyright 2012 Johns Hopkins University (Author: Daniel Povey).  Apache 2.0.
# This script, which will generally be called from other neural-net training
# scripts, extracts the training examples used to train the neural net

# Begin configuration section.
cmd=run.pl
stage=0
feat_type=raw
num_jobs_nnet=4    # Number of neural net jobs to run in parallel
splice_width=4
num_jobs_nnet=4
iters_per_epoch=2

. ./path.sh
. ./utils/parse_options.sh


if [ $# != 3 ]; then
  echo "Usage: steps/nnet2/get_egs.sh [opts] <data> <ali-dir> <exp-dir>"
  echo " e.g.: steps/nnet2/get_egs.sh data/train exp/tri3_ali exp/tri4_nnet"
  echo ""
  echo "Main options (for others, see top of script file)"
  echo "  --cmd (utils/run.pl;utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-jobs-nnet <num-jobs;16>                    # Number of parallel jobs to use for main neural net"
  echo "                                                   # training (will affect results as well as speed; try 8, 16)"
  echo "                                                   # Note: if you increase this, you may want to also increase"
  echo "                                                   # the learning rate."
  echo "                                                   # to use as input to the neural net."
  echo "  --splice-width <width;4>                         # Number of frames on each side to append for feature input"
  echo "  --stage <stage|0>                                # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."
  exit 1;
fi


data_dir=$1
ali_dir=$2
exp_dir=$3


# check for some files
for f in \
    $data_dir/feats.scp \
    $ali_dir/ali.1.gz \
    $ali_dir/final.mdl \
    $ali_dir/tree \
    $ali_dir/num_jobs; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done


# get number of jobs in alignment dir
nj=`cat $ali_dir/num_jobs` || exit 1;
sdata=$data_dir/split$nj

# Define training features
feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"

    
if [ $stage -le 1 ]; then
    
    # Making soft links to storage directories.  This is a no-up unless
    # the subdirectory $exp_dir/egs/storage/ exists.  See utils/create_split_dir.pl
    for x in `seq 1 $num_jobs_nnet`; do
        for y in `seq 0 $[$iters_per_epoch-1]`; do
            utils/create_data_link.pl $exp_dir/egs/egs.$x.$y.ark
            utils/create_data_link.pl $exp_dir/egs/egs_tmp.$x.$y.ark
        done
        for y in `seq 1 $nj`; do
            utils/create_data_link.pl $exp_dir/egs/egs_orig.$x.$y.ark
        done
    done
    
    remove () { for x in $*; do [ -L $x ] && rm $(readlink -f $x); rm $x; done }
    
fi



if [ $stage -le 2 ]; then
        
    echo "$0: Creating training examples."
 
    mkdir -p $exp_dir/egs

    # train_simple.sh uses this info:
    echo $num_jobs_nnet >$exp_dir/egs/num_jobs_nnet
    echo $iters_per_epoch >$exp_dir/egs/iters_per_epoch
    
    # create $num_jobs_nnet separate files with training examples.    
    egs_list=
    for n in `seq 1 $num_jobs_nnet`; do
        egs_list="$egs_list ark:$exp_dir/egs/egs_orig.$n.JOB.ark"
    done

    $cmd JOB=1:$nj $exp_dir/log/get_egs.JOB.log \
        nnet-get-egs \
            --left-context="$splice_width" \
            --right-context="$splice_width" \
            "$feats" \
            "ark,s,cs:gunzip -c $ali_dir/ali.JOB.gz | ali-to-pdf $ali_dir/final.mdl ark:- ark:- | ali-to-post ark:- ark:- |" \
            ark:- \| \
        nnet-copy-egs \
            ark:- \
            $egs_list \
            || exit 1;
fi


if [ $stage -le 4 ]; then

    echo "$0: Rearranging training examples for different parallel jobs."

    # combine all the "egs_orig.JOB.*.scp" (over the $nj splits of the data) and
    # then split into multiple parts egs.JOB.*.scp for different parts of the
    # data, 0 .. $iters_per_epoch-1.
    
    if [ $iters_per_epoch -eq 1 ]; then

        echo "$0: Since iters-per-epoch == 1, just concatenating the data."

        for n in `seq 1 $num_jobs_nnet`; do
            cat $exp_dir/egs/egs_orig.$n.*.ark > $exp_dir/egs/egs_tmp.$n.0.ark \
                || exit 1;
            remove $exp_dir/egs/egs_orig.$n.*.ark 
        done

    else # We'll have to split it up using nnet-copy-egs.
        egs_list=
        for n in `seq 0 $[$iters_per_epoch-1]`; do
            egs_list="$egs_list ark:$exp_dir/egs/egs_tmp.JOB.$n.ark"
        done
        # note, the "|| true" below is a workaround for NFS bugs
        # we encountered running this script with Debian-7, NFS-v4.
        $cmd JOB=1:$num_jobs_nnet $exp_dir/log/split_egs.JOB.log \
            nnet-copy-egs \
                --srand=JOB \
                "ark:cat $exp_dir/egs/egs_orig.JOB.*.ark|" \
                $egs_list \
                || exit 1;

        remove $exp_dir/egs/egs_orig.*.*.ark  2>/dev/null
    fi
fi


if [ $stage -le 5 ]; then

    echo "$0: Shuffle training examples."

    # Next, shuffle the order of the examples in each of those files.
    # Each one should not be too large, so we can do this in memory.
    # in order to avoid stressing the disk, these won't all run at once
    
    for n in `seq 0 $[$iters_per_epoch-1]`; do
        $cmd JOB=1:$num_jobs_nnet $exp_dir/log/shuffle.$n.JOB.log \
            nnet-shuffle-egs \
                "--srand=\$[JOB+($num_jobs_nnet*$n)]" \
                ark:$exp_dir/egs/egs_tmp.JOB.$n.ark \
                ark:$exp_dir/egs/egs.JOB.$n.ark;

        remove $exp_dir/egs/egs_tmp.*.$n.ark
    done
fi


echo "$0: Finished preparing training examples."
