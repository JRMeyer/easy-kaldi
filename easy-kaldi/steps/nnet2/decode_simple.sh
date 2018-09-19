#!/bin/bash

# Copyright 2012-2013  Johns Hopkins University (Author: Daniel Povey).
# Apache 2.0.

# This script does decoding with a neural-net.  If the neural net was built on
# top of fMLLR transforms from a conventional system, you should provide the
# --transform-dir option.

# Begin configuration section.
stage=1
nj=4 # number of decoding jobs.  If --transform-dir set, must match that number!
acwt=0.1  # Just a default value, used for adaptation and beam-pruning..
cmd=run.pl
beam=15.0
max_active=7000
min_active=200
lattice_beam=8.0 # Beam we use in lattice generation.
num_threads=4
feat_type=raw

. ./path.sh; # source the path.
. ./utils/parse_options.sh || exit 1;

if [ $# -ne 6 ]; then
  echo "Usage: $0 [options] <graph-dir> <data-dir> <am-model-file> <unknown_phone> <silence_phone> <decode-dir>"
  echo "main options (for others, see top of script file)"
  echo "  --transform-dir <decoding-dir>           # directory of previous decoding"
  echo "                                           # where we can find transforms for SAT systems."
  echo "  --config <config-file>                   # config containing options"
  echo "  --nj <nj>                                # number of parallel jobs"
  echo "  --cmd <cmd>                              # Command to run in parallel with"
  echo "  --beam <beam>                            # Decoding beam; default 15.0"
  echo "  --num-threads <n>                        # number of threads to use, default 1."
  exit 1;
fi

graph_dir=$1
data_dir=$2
model=$3
unknown_phone=$4
silence_phone=$5
decode_dir=$6

# make sure graph, dnn, and features are in place
for f in \
    $graph_dir/HCLG.fst \
    $model \
    $data_dir/feats.scp;
    do [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

# make data and log dirs
sdata=$data_dir/split$nj;
mkdir -p $decode_dir/log
[[ -d $sdata && $data_dir/feats.scp -ot $sdata ]] \
    || split_data.sh $data_dir $nj \
    || exit 1;
echo $nj > $decode_dir/num_jobs



if [ $stage -le 1 ]; then

    printf "\n#### BEGIN DECODING ####\n"

    # Define testing audio features
    feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |"

    # Decode features with AM and graph
    $cmd --num-threads $num_threads JOB=1:$nj $decode_dir/log/decode.JOB.log \
        nnet-latgen-faster-parallel \
            --max-active=$max_active \
            --min-active=$min_active \
            --beam=$beam \
            --lattice-beam=$lattice_beam \
            --acoustic-scale=$acwt \
            --allow-partial=true \
            --word-symbol-table=$graph_dir/words.txt \
            "$model" \
            $graph_dir/HCLG.fst \
            "$feats" \
            "ark:|gzip -c > $decode_dir/lat.JOB.gz" \
            || exit 1;

    printf "\n#### END DECODING ####\n"

fi



if [ $stage -le 2 ]; then

    printf "\n#### BEGIN SCORING ####\n"
    
    local/score.sh \
        --cmd "$cmd" \
        $data_dir \
        $graph_dir \
        $decode_dir \
        $unknown_phone \
        $silence_phone \
        || exit 1;

    printf "\n#### END SCORING ####\n"

fi

exit 0;
