#!/bin/bash

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0


# Begin configuration.
stage=-4 #  This allows restarting after partway, when something when wrong.
config=
cmd=run.pl
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
realign_iters="10 20 30";
num_iters=35    # Number of iterations of training
max_iter_inc=25 # Last iter to increase #Gauss on.
beam=10
careful=false
retry_beam=40
boost_silence=1.0 # Factor by which to boost silence likelihoods in alignment
power=0.25 # Exponent for number of gaussians according to occurrence counts
cluster_thresh=-1  # for build-tree control final bottom-up clustering of leaves
norm_vars=false # deprecated.  Prefer --cmvn-opts "--norm-vars=true"
                # use the option --cmvn-opts "--norm-means=false"


echo "$0 $@"  # Print the command line for logging

[ -f path.sh ] && . ./path.sh;
. parse_options.sh || exit 1;

if [ $# != 6 ]; then
   echo "Usage: steps/train_deltas.sh <num-leaves> <tot-gauss> <data-dir> <lang-dir> <alignment-dir> <exp-dir>"
   echo "e.g.: steps/train_deltas.sh 2000 10000 data/train_si84_half data/lang exp/mono_ali exp/tri1"
   echo "main options (for others, see top of script file)"
   echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
   echo "  --config <config-file>                           # config containing options"
   echo "  --stage <stage>                                  # stage to do partial re-run from."
   exit 1;
fi

num_leaves=$1
tot_gauss=$2
data_dir=$3
lang_dir=$4
ali_dir=$5
exp_dir=$6
verbose=false


for f in $ali_dir/final.mdl \
             $ali_dir/ali.1.gz \
             $data_dir/feats.scp \
             $lang_dir/phones.txt; do
    [ ! -f $f ] && echo "train_deltas.sh: no such file $f" && exit 1;
done

num_gauss=$num_leaves
# per-iter increment for #Gauss
inc_gauss=$[($tot_gauss-$num_gauss)/$max_iter_inc]

echo "num_leaves = ${num_leaves}"
echo "tot_gauss = ${tot_gauss}"

oov=`cat $lang_dir/oov.int` || exit 1;
ciphonelist=`cat $lang_dir/phones/context_indep.csl` || exit 1;
nj=`cat $ali_dir/num_jobs` || exit 1;
mkdir -p $exp_dir/log
echo $nj > $exp_dir/num_jobs

sdata=$data_dir/split$nj;
# split_data.sh $data_dir $nj || exit 1;

echo $cmvn_opts  > $exp_dir/cmvn_opts


if [ $stage -le -3 ]; then

    feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk"
    feats="$feats scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |"
    feats="$feats add-deltas ark:- ark:- |"

    echo "$0: accumulating tree stats"

    $cmd JOB=1:$nj $exp_dir/log/acc_tree.JOB.log \
        acc-tree-stats \
            $context_opts \
            --ci-phones=$ciphonelist \
            $ali_dir/final.mdl \
            "$feats" \
            "ark:gunzip -c $ali_dir/ali.JOB.gz|" \
            $exp_dir/JOB.treeacc \
            || exit 1;

    sum-tree-stats \
        $exp_dir/treeacc \
        $exp_dir/*.treeacc \
        2>$exp_dir/log/sum_tree_acc.log \
        || exit 1;

fi



if [ $stage -le -2 ]; then

    echo "$0: getting questions for tree-building, via clustering"

    cluster-phones \
        $context_opts \
        $exp_dir/treeacc \
        $lang_dir/phones/sets.int \
        $exp_dir/questions.int \
        2> $exp_dir/log/questions.log \
        || exit 1;

    cat $lang_dir/phones/extra_questions.int >> $exp_dir/questions.int

    compile-questions \
        $context_opts \
        $lang_dir/topo \
        $exp_dir/questions.int \
        $exp_dir/questions.qst \
        2>$exp_dir/log/compile_questions.log \
        || exit 1;

    echo "$0: building the tree"

    $cmd $exp_dir/log/build_tree.log \
        build-tree \
            $context_opts \
            --verbose=1 \
            --max-leaves=$num_leaves \
            --cluster-thresh=$cluster_thresh \
            $exp_dir/treeacc \
            $lang_dir/phones/roots.int \
            $exp_dir/questions.qst \
            $lang_dir/topo \
            $exp_dir/tree \
            || exit 1;
fi



if [ $stage -le -2 ]; then

    echo "$0: Initializing triphone model"
    
    $cmd $exp_dir/log/init_model.log \
         gmm-init-model \
            --write-occs=$exp_dir/1.occs \
            $exp_dir/tree \
            $exp_dir/treeacc \
            $lang_dir/topo \
            $exp_dir/1.mdl \
            || exit 1;
    
    if grep 'no stats' $exp_dir/log/init_model.log; then
        echo "** Above warnings about 'no stats' mean you have phones **"
        echo "** (or groups of phones) in your phone set that had no data. **"
        echo "** You should probably figure out whether something went wrong **"
        echo "** or whether your data just doesn't have examples of those **"
        echo "** phones. **"
    fi
    
    gmm-mixup \
        --mix-up=$num_gauss \
        $exp_dir/1.mdl \
        $exp_dir/1.occs \
        $exp_dir/1.mdl \
        2>$exp_dir/log/mixup.log \
        || exit 1;
fi



if [ $stage -le -1 ]; then

    echo "$0: converting alignments from $ali_dir to use current senomes"

    $cmd JOB=1:$nj $exp_dir/log/convert.JOB.log \
        convert-ali \
            $ali_dir/final.mdl \
            $exp_dir/1.mdl \
            $exp_dir/tree \
            "ark:gunzip -c $ali_dir/ali.JOB.gz|" \
            "ark:|gzip -c >$exp_dir/ali.JOB.gz" \
            || exit 1;
fi



if [ $stage -le 0 ]; then

    echo "$0: compiling training graphs (HMMs) of transcripts"

    $cmd JOB=1:$nj $exp_dir/log/compile_graphs.JOB.log \
        compile-train-graphs \
            $exp_dir/tree \
            $exp_dir/1.mdl \
            $lang_dir/L.fst  \
            "ark:utils/sym2int.pl --map-oov $oov -f 2- $lang_dir/words.txt < $sdata/JOB/text |" \
            "ark:|gzip -c >$exp_dir/fsts.JOB.gz" \
            || exit 1;
fi



if [ $stage -le 1 ]; then

    x=1
    while [ $x -lt $num_iters ]; do
        
        printf "\n$0: training pass $x\n"
        
        if [ $stage -le $x ]; then
            
            if echo $realign_iters | grep -w $x >/dev/null; then
                
                printf "$0: E-Step in EM Algorithm\n"
                
                mdl="gmm-boost-silence --boost=$boost_silence `cat $lang_dir/phones/optional_silence.csl`"
                mdl="$mdl $exp_dir/$x.mdl - |"

                $cmd JOB=1:$nj $exp_dir/log/align.$x.JOB.log \
                    gmm-align-compiled \
                        $scale_opts \
                        --beam=$beam \
                        --retry-beam=$retry_beam \
                        --careful=$careful \
                        "$mdl" \
                        "ark:gunzip -c $exp_dir/fsts.JOB.gz|" "$feats" \
                        "ark:|gzip -c >$exp_dir/ali.JOB.gz" \
                        || exit 1;
            fi

        printf "$0: M-Step in EM Algorithm\n"

        $cmd JOB=1:$nj $exp_dir/log/acc.$x.JOB.log \
            gmm-acc-stats-ali \
                $exp_dir/$x.mdl \
                "$feats" \
                "ark,s,cs:gunzip -c $exp_dir/ali.JOB.gz|" \
                $exp_dir/$x.JOB.acc \
                || exit 1;

        $cmd $exp_dir/log/update.$x.log \
            gmm-est \
                --mix-up=$num_gauss \
                --power=$power \
                --write-occs=$exp_dir/$[$x+1].occs \
                $exp_dir/$x.mdl \
                "gmm-sum-accs - $exp_dir/$x.*.acc |" \
                $exp_dir/$[$x+1].mdl \
                || exit 1;
        
        fi
        
        [ $x -le $max_iter_inc ] && num_gauss=$[$num_gauss+$inc_gauss];
        
        x=$[$x+1];
        
    done
    
    cp $exp_dir/$x.mdl $exp_dir/final.mdl
    cp $exp_dir/$x.occs $exp_dir/final.occs

fi

printf "\n$0: Done training system with delta+delta-delta features in ${exp_dir}\n\n"
