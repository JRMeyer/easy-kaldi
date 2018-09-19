#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# USAGE:
#

# INPUT:
#
#       experiemnt/
#           monophones
#
#       audio_dir/
#          all-audio-files-here.wav
#
#    config_dir/
#       mfcc.conf
#       topo_orig.proto
#
# OUTPUT:
#
#    experiment_dir
#    mfcc_dir
#    data_dir
#    train_dir
#    test_dir
# 


# Computes training alignments using a model with delta or
# LDA+MLLT features.

# If you supply the "--use-graphs true" option, it will use the training
# graphs from the source directory (where the model is).  In this
# case the number of jobs must match with the source directory.


nj=4
cmd=run.pl
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
beam=10
retry_beam=40
careful=false
boost_silence=1.0 # Factor by which to boost silence during alignment.


. ./path.sh || exit 1;
. ./utils/parse_options.sh || exit 1;

if [ $# != 4 ]; then
   echo "usage: steps/align_si.sh <data-dir> <lang-dir> <src-dir> <align-dir>"
   echo "e.g.:  steps/align_si.sh data/train data/lang exp/tri1 exp/tri1_ali"
   echo "main options (for others, see top of script file)"
   echo "  --config <config-file>                           # config containing options"
   echo "  --nj <nj>                                        # number of parallel jobs"
   echo "  --use-graphs true                                # use graphs in src-dir"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   exit 1;
fi

data_dir=$1
lang_dir=$2
src_dir=$3
align_dir=$4


for f in \
    $lang_dir/oov.int \
    $src_dir/tree \
    $src_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1;
done


mkdir -p $align_dir/log
echo $nj > $align_dir/num_jobs
sdata=$data_dir/split$nj

# frame-splicing options
splice_opts=`cat $src_dir/splice_opts`
cp $src_dir/splice_opts $align_dir
# cmvn option
cmvn_opts=`cat $src_dir/cmvn_opts`
cp $src_dir/cmvn_opts $align_dir
# delta options
delta_opts=`cat $src_dir/delta_opts`
cp $src_dir/delta_opts $align_dir

# if the features are new, split data
[[ -d $sdata && $data_dir/feats.scp -ot $sdata ]] \
    || split_data.sh $data_dir $nj \
    || exit 1;

cp $src_dir/{tree,final.mdl} $align_dir \
    || exit 1;

cp $src_dir/final.occs $align_dir;



if [ -f $src_dir/final.mat ]; then feat_type=lda; else feat_type=delta; fi
echo "$0: feature type is $feat_type"

case $feat_type in

    delta) feats="ark,s,cs:apply-cmvn $cmvn_opts "
        feats+="--utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp "
        feats+="scp:$sdata/JOB/feats.scp ark:- | add-deltas $delta_opts ark:- "
        feats+="ark:- |";;

    lda) feats="ark,s,cs:apply-cmvn $cmvn_opts "
        feats+="--utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp "
        feats+="scp:$sdata/JOB/feats.scp ark:- | splice-feats $splice_opts "
        feats+="ark:- ark:- | transform-feats $src_dir/final.mat ark:- ark:- |"
        cp $src_dir/final.mat $src_dir/full.mat $align_dir;;

    *) echo "$0: invalid feature type $feat_type" && exit 1;
esac


printf "$0: Aligning data in $data_dir using model from $src_dir putting alignments in $align_dir\n" 

mdl="gmm-boost-silence --boost=$boost_silence `cat $lang_dir/phones/optional_silence.csl` $align_dir/final.mdl - |"

oov=`cat $lang_dir/oov.int` || exit 1;

transcriptions="ark:utils/sym2int.pl --map-oov $oov -f 2- $lang_dir/words.txt $sdata/JOB/text|";


# We could just use gmm-align in the next line,  but it's less efficient as 
# it compiles the training graphs one by one.
$cmd JOB=1:$nj $align_dir/log/align.JOB.log \
    compile-train-graphs \
        $align_dir/tree \
        $align_dir/final.mdl \
        $lang_dir/L.fst \
        "$transcriptions" \
        ark:- \| \
    gmm-align-compiled \
        $scale_opts \
        --beam=$beam \
        --retry-beam=$retry_beam \
        --careful=$careful \
        "$mdl" \
        ark:- "$feats" \
        "ark,t:|gzip -c >$align_dir/ali.JOB.gz" \
    || exit 1;
