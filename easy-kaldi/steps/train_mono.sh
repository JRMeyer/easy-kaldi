#!/bin/bash
# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# USAGE:
#
#  ./steps/train_mono.sh \
#      data_dir/train_dir \
#      data_dir/lang_dir \
#      experiment_dir/monophones;

# INPUT:
#
#    /data/
#        train/
#            feats.scp
#
#        lang/
#            oov.int
#            topo
#            L.fst
#            words.txt
#
#            phones/
#                sets.int
#                optional_silence.csl

# OUTPUT:
#
#     /experiment_dir/
#          monophones/
#              final.mdl
#              tree


# Flat start and monophone training, with delta-delta features.
# This script applies cepstral mean normalization (per speaker).

beam=6 # will change to 10 below after 1st pass
nj=4
cmd=run.pl
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
num_iters=40    # Number of iterations of training
max_iter_inc=30 # Last iter to increase #Gauss on.
totgauss=1000 # Target #Gaussians.
careful=false
boost_silence=1.0 # Factor by which to boost silence likelihoods in alignment
realign_iters="1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 23 26 29 32 35 38";
config= # name of config file.
stage=-4
power=0.25 # exponent to determine number of gaussians from occurrence counts
cmvn_opts="--norm-vars=true $cmvn_opts"


. ./path.sh || exit  1;
. ./utils/parse_options.sh || exit 1;


if [ $# != 3 ]; then
  echo "Usage: steps/train_mono.sh [options] <data-dir> <lang-dir> <exp-dir>"
  echo " e.g.: steps/train_mono.sh data/train.1k data/lang exp/mono"
  echo "main options (for others, see top of script file)"
  echo "  --config <config-file>                    # config containing options"
  echo "  --nj <nj>                                   # number of parallel jobs"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  exit 1;
fi


data_dir=$1
lang_dir=$2
exp_dir=$3


for f in \
    $lang_dir/phones/sets.int \
    $lang_dir/oov.int;
    do [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done        




if [ $stage -le -4 ]; then

    echo "### Define audio features ###"

    mkdir -p $exp_dir
    echo $cmvn_opts > $exp_dir/cmvn_opts # keep track of options to CMVN.

    # the dirs we already split data into
    sdata=$data_dir/split$nj;

    feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk"
    feats="$feats scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |"
    feats="$feats add-deltas ark:- ark:- |"
    
    # get the feature dimensions of the data just from a small section (JOB 1)
    feats_example="`echo $feats | sed s/JOB/1/g`";
    feat_dim=`feat-to-dim "$feats_example" -` || exit 1

fi



if [ $stage -le -3 ]; then

    echo "$0: Initializing monophone system"
    
    $cmd JOB=1 $exp_dir/log/init.log \
        gmm-init-mono \
            --shared-phones=$lang_dir/phones/sets.int \
            "--train-feats=$feats subset-feats --n=10 ark:- ark:-|" \
            $lang_dir/topo \
            $feat_dim \
            $exp_dir/0.mdl \
            $exp_dir/tree \
            || exit 1;

    num_gauss=`gmm-info --print-args=false $exp_dir/0.mdl | grep gaussians | awk '{print $NF}'`

    # per-iter increment for #Gauss
    inc_gauss=$[($totgauss-$num_gauss)/$max_iter_inc]

fi



if [ $stage -le -2 ]; then

    echo "$0: Compiling monophone training graphs"

    oov_sym=`cat $lang_dir/oov.int` || exit 1;

    $cmd JOB=1:$nj $exp_dir/log/compile_graphs.JOB.log \
        compile-train-graphs \
            $exp_dir/tree \
            $exp_dir/0.mdl  \
            $lang_dir/L.fst \
            "ark:sym2int.pl --map-oov $oov_sym -f 2- $lang_dir/words.txt < $sdata/JOB/text|" \
            "ark:|gzip -c >$exp_dir/fsts.JOB.gz" \
            || exit 1;
fi



if [ $stage -le -1 ]; then

    echo ""
    echo "##########################################"
    echo "### BEGIN FLATSTART MONOPHONE TRAINING ###"
    echo "##########################################"

    printf "$0: Aligning data from flat start (pass 0)\n"

    $cmd JOB=1:$nj $exp_dir/log/align.0.JOB.log \
        align-equal-compiled \
            "ark:gunzip -c $exp_dir/fsts.JOB.gz|" \
            "$feats" \
            ark,t:-  \| \
        gmm-acc-stats-ali \
            --binary=true \
            $exp_dir/0.mdl \
            "$feats" \
            ark:- \
            $exp_dir/0.JOB.acc \
            || exit 1;

    printf "$0: Estimating model from flat start alignments\n"

    gmm-est \
        --min-gaussian-occupancy=3  \
        --mix-up=$num_gauss \
        --power=$power \
        $exp_dir/0.mdl \
        "gmm-sum-accs - $exp_dir/0.*.acc|" \
        $exp_dir/1.mdl \
        2> $exp_dir/log/update.0.log \
        || exit 1;

fi



if [ $stage -le 0 ]; then

    echo ""
    echo "########################################"
    echo "### BEGIN MAIN EM MONOPHONE TRAINING ###"
    echo "########################################"

    x=1
    while [ $x -lt $num_iters ]; do
        
        printf "\n$0: Pass $x\n"
        
        if [ $stage -le $x ]; then
            
            # if this is an iteration where we realign (E-step) data
            if echo $realign_iters | grep -w $x >/dev/null; then
                
                printf "$0: Expectation Step in EM Algorithm\n"
                
                mdl="gmm-boost-silence --boost=$boost_silence"
                mdl="$mdl `cat $lang_dir/phones/optional_silence.csl`"
                mdl="$mdl $exp_dir/$x.mdl - |"
                
                $cmd JOB=1:$nj $exp_dir/log/align.$x.JOB.log \
                    gmm-align-compiled \
                        $scale_opts \
                        --beam=$beam \
                        --retry-beam=$[$beam*4] \
                        --careful=$careful \
                        "$mdl" \
                        "ark:gunzip -c $exp_dir/fsts.JOB.gz|" \
                        "$feats" \
                        "ark,t:|gzip -c >$exp_dir/ali.JOB.gz" \
                        || exit 1;
            fi

            printf "$0: Maximize-Step in EM Algorithm\n"
            
            $cmd JOB=1:$nj $exp_dir/log/acc.$x.JOB.log \
                gmm-acc-stats-ali  \
                    $exp_dir/$x.mdl \
                    "$feats" "ark:gunzip -c $exp_dir/ali.JOB.gz|" \
                    $exp_dir/$x.JOB.acc \
                    || exit 1;
        
            $cmd $exp_dir/log/update.$x.log \
                 gmm-est \
                    --write-occs=$exp_dir/$[$x+1].occs \
                    --mix-up=$num_gauss \
                    --power=$power \
                    $exp_dir/$x.mdl \
                    "gmm-sum-accs - $exp_dir/$x.*.acc|" \
                    $exp_dir/$[$x+1].mdl \
                    || exit 1;
            
        fi

        
        if [ $x -le $max_iter_inc ]; then
            num_gauss=$[$num_gauss+$inc_gauss];
        fi

        x=$[$x+1]
        
    done

    cp $exp_dir/$x.mdl $exp_dir/final.mdl
    cp $exp_dir/$x.occs $exp_dir/final.occs
fi
