#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# Begin configuration section.  
transform_dir=   # this option won't normally be used, but it can be used if you
                 # supply existing fMLLR transforms when decoding.
iter=
model= # You can specify the model to use (e.g. if you want to use the .alimdl)
stage=0
nj=1
cmd=run.pl
max_active=7000
beam=12.0
lattice_beam=7.0
acwt=0.083333 # note: only really affects pruning (scoring is on lattices).
num_threads=1 # if >1, will use gmm-latgen-faster-parallel
parallel_opts=  # ignored now.
scoring_opts=
# note: there are no more min-lmwt and max-lmwt options, instead use
# e.g. --scoring-opts "--min-lmwt 1 --max-lmwt 20"
skip_scoring=false
# End configuration section.

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;


echo $0 $#


if [ $# != 6 ]; then
    echo "Usage: steps/decode.sh [options] <graph-dir> <data-dir> <decode-dir> <unknown_phone> <silence_phone>"
    echo "... where <decode-dir> is assumed to be a sub-directory of the directory"
    echo " where the model is."
    echo "e.g.: steps/decode.sh exp/mono/graph_tgpr data_dir/test_dev93 exp/mono/decode_dev93_tgpr"
    echo ""
    echo "This script works on CMN + (delta+delta-delta | LDA+MLLT) features; it works out"
    echo "what type of features you used (assuming it's one of these two)"
    echo ""
    echo "main options (for others, see top of script file)"
    echo "  --config <config-file>                           # config containing options"
    echo "  --nj <nj>                                        # number of parallel jobs"
    echo "  --iter <iter>                                    # Iteration of model to test."
    echo "  --model <model>                                  # which model to use (e.g. to"
    echo "                                                   # specify the final.alimdl)"
    echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
    echo "  --transform-dir <trans-dir>                      # dir to find fMLLR transforms "
    echo "  --acwt <float>                                   # acoustic scale used for lattice generation "
    echo "  --scoring-opts <string>                          # options to local/score.sh"
    echo "  --num-threads <n>                                # number of threads to use, default 1."
    echo "  --parallel-opts <opts>                           # ignored now, present for historical reasons."
    exit 1;
fi


graph=$1
model=$2
data_dir=$3
decode_dir=$4
unknown_phone=$5
silence_phone=$6

graph_dir=`dirname $graph`
model_dir=`dirname $model`
split_data_dir=$data_dir/split$nj;

# Check for feats + model + graph
for f in $split_data_dir/1/feats.scp \
             $split_data_dir/1/cmvn.scp \
             $model \
             $graph; do
    [ ! -f $f ] && echo "decode.sh: no such file $f" && exit 1;
done


if [ -f $model_dir/final.mat ]; then
    feat_type=lda;
else
    feat_type=delta;
fi

echo "decode.sh: feature type is $feat_type";


splice_opts=`cat $model_dir/splice_opts 2>/dev/null` # frame-splicing options.
cmvn_opts=`cat $model_dir/cmvn_opts 2>/dev/null`
delta_opts=`cat $model_dir/delta_opts 2>/dev/null`

thread_string=
[ $num_threads -gt 1 ] && thread_string="-parallel --num-threads=$num_threads" 

case $feat_type in
    delta) feats="ark,s,cs:apply-cmvn $cmvn_opts "
        feats+="--utt2spk=ark:$split_data_dir/JOB/utt2spk "
        feats+="scp:$split_data_dir/JOB/cmvn.scp "
        feats+="scp:$split_data_dir/JOB/feats.scp ark:- | add-deltas "
        feats+="$delta_opts ark:- ark:- |";;

    lda) feats="ark,s,cs:apply-cmvn $cmvn_opts "
        feats+="--utt2spk=ark:$split_data_dir/JOB/utt2spk "
        feats+="scp:$split_data_dir/JOB/cmvn.scp "
        feats+="scp:$split_data_dir/JOB/feats.scp ark:- | splice-feats "
        feats+="$splice_opts ark:- ark:- | transform-feats "
        feats+="$model_dir/final.mat ark:- ark:- |";;

    *) echo "Invalid feature type $feat_type" && exit 1;
esac


 # add transforms to features if we transformed in training
if [ ! -z "$transform_dir" ]; then
    
    echo "Using fMLLR transforms from $transform_dir"

    [ ! -f $transform_dir/trans.1 ] && \
        echo "Expected $transform_dir/trans.1 to exist."
    [ ! -s $transform_dir/num_jobs ] && \
        echo "$0: expected $transform_dir/num_jobs to contain number of jobs." \
        && exit 1;

    nj_orig=$(cat $transform_dir/num_jobs)

    if [ $nj -ne $nj_orig ]; then
        # Copy the transforms into an archive with an index.
        echo "$0: num-jobs for transforms mismatches, so copying them."
        for n in $(seq $nj_orig); do cat $transform_dir/trans.$n; done | \
            copy-feats \
            ark:- ark,scp:$decode_dir/trans.ark,$decode_dir/trans.scp \
            || exit 1;
        feats="$feats transform-feats ";
        feats+="--utt2spk=ark:$split_data_dir/JOB/utt2spk ";
        feats+="scp:$decode_dir/trans.scp ark:- ark:- |";

    else
        # number of jobs matches with alignment dir.
        feats="$feats transform-feats ";
        feats+="--utt2spk=ark:$split_data_dir/JOB/utt2spk ";
        feats+="ark:$transform_dir/trans.JOB ark:- ark:- |";
    fi
fi


if [ $stage -le 0 ]; then
    if [ -f "$graph_dir/num_pdfs" ]; then
        [ "`cat $graph_dir/num_pdfs`" -eq `am-info --print-args=false $model | grep pdfs | awk '{print $NF}'` ] \
            || { echo "Mismatch in number of pdfs with $model"; exit 1; }
    fi

    $cmd --num-threads $num_threads JOB=1:$nj $decode_dir/log/decode.JOB.log \
         gmm-latgen-faster$thread_string \
         --max-active=$max_active \
         --beam=$beam \
         --lattice-beam=$lattice_beam \
         --acoustic-scale=$acwt \
         --allow-partial=true \
         --word-symbol-table=$graph_dir/words.txt \
         $model \
         $graph \
         "$feats" \
         "ark:|gzip -c > $decode_dir/lat.JOB.gz" \
        || exit 1;
fi

if ! $skip_scoring ; then
    [ ! -x local/score.sh ] && \
        echo "local/score.sh does not exist or not executable." && exit 1;

    local/score.sh --cmd "$cmd" \
        $data_dir \
        $graph_dir \
        $decode_dir \
        $unknown_phone \
        $silence_phone \
        || { echo "$0: Scoring failed. (ignore by '--skip-scoring true')"; exit 1; }
fi

exit 0;
