#!/bin/bash

# Copyright 2012 Johns Hopkins University (Author: Daniel Povey).  Apache 2.0.
# This script, which will generally be called from other neural-net training
# scripts, extracts the training examples used to train the neural net 
#, and puts them in separate archives.

# Josh Meyer - I took out extra diagnostic examples


# Begin configuration section.
cmd=run.pl
stage=0
feat_type=raw
splice_width=4 # meaning +- 4 frames on each side for second LDA
lda_dim=40


. ./path.sh
. ./utils/parse_options.sh


if [ $# != 4 ]; then
  echo "Usage: steps/nnet2/get_lda.sh [opts] <data> <lang> <ali-dir> <exp-dir>"
  echo " e.g.: steps/nnet2/get_lda.sh data/train data/lang exp/tri3_ali exp/tri4_nnet"
  echo " As well as extracting the examples, this script will also do the LDA computation,"
  echo " if --est-lda=true (default:true)"
  echo ""
  echo "Main options (for others, see top of script file)"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --splice-width <width|4>                         # Number of frames on each side to append for feature input"
  echo "                                                   # (note: we splice processed, typically 40-dimensional frames"
  echo "  --stage <stage|0>                                # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."
  exit 1;
fi

data_dir=$1
lang_dir=$2
ali_dir=$3
exp_dir=$4

# Check some files.
for f in \
    $data_dir/feats.scp \
    $ali_dir/ali.1.gz \
    $ali_dir/final.mdl \
    $ali_dir/tree \
    $ali_dir/num_jobs; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

nj=`cat $ali_dir/num_jobs` || exit 1;
sdata=$data_dir/split$nj

# feat_dim and lda_dim get used in train_simple.sh to define nnet dimensions
feat_dim=`feat-to-dim scp:$sdata/1/feats.scp -` || exit 1;
echo $feat_dim > $exp_dir/feat_dim
echo $lda_dim > $exp_dir/lda_dim

# Define spliced features
spliced_feats="ark,s,cs:splice-feats --left-context=$splice_width --right-context=$splice_width scp:$sdata/JOB/feats.scp ark:- |"


if [ $stage -le 0 ]; then

    echo "$0: Accumulating LDA statistics."

    # Convert alignments to posteriors | Accumulate LDA stats based on pdf-ids
    # Here, we could apply weight to silences in posteriors, before acc-lda
    
    $cmd JOB=1:$nj $exp_dir/log/lda_acc.JOB.log \
        ali-to-post \
            "ark:gunzip -c $ali_dir/ali.JOB.gz|" \
            ark:- \| \
        acc-lda \
            $ali_dir/final.mdl \
            "$spliced_feats" \
            ark,s,cs:- \
            $exp_dir/lda.JOB.acc \
            || exit 1;
    
fi


if [ $stage -le 1 ]; then

  echo "$0: Summing LDA statistics."

    sum-lda-accs \
        $exp_dir/lda.acc \
        $exp_dir/lda.*.acc \
        2>$exp_dir/log/lda_sum.log \
        || exit 1;

fi


if [ $stage -le 2 ]; then
   
  echo "$0: Getting LDA transformation matrix."

  nnet-get-feature-transform \
      --dim=$lda_dim \
      $exp_dir/lda.mat \
      $exp_dir/lda.acc \
      2>$exp_dir/log/lda_est.log \
      || exit 1;

fi


echo "$0: Finished estimating LDA"
