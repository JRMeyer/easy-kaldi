#!/bin/bash

# Copyright 2012-2014  Johns Hopkins University (Author: Daniel Povey). 
#           2013  Xiaohui Zhang
#           2013  Guoguo Chen
#           2014  Vimal Manohar
# Apache 2.0.
#

# Begin configuration section.
cmd=run.pl
stage=-4
num_epochs=15      # Number of epochs of training
initial_learning_rate=0.04
final_learning_rate=0.004
bias_stddev=0.5
hidden_layer_dim=0
add_layers_period=2 # by default, add new layers every 2 iterations.
num_hidden_layers=3
minibatch_size=128 # by default use a smallish minibatch size for neural net
                   # training; this controls instability which would otherwise
                   # be a problem with multi-threaded update. 
num_threads=4   # Number of jobs to run in parallel.
splice_width=4 # meaning +- 4 frames on each side for second LDA
lda_dim=40
feat_type=raw  # raw, untransformed features (probably MFCC or PLP)
iters_per_epoch=5

. ./path.sh || exit 1; # make sure we have a path.sh script
. ./utils/parse_options.sh || exit 1;


if [ $# != 4 ]; then
  echo "Usage: $0 [opts] <data> <lang> <ali-dir> <exp-dir>"
  echo " e.g.: $0 data/train data/lang exp/tri3_ali exp/tri4_nnet"
  echo ""
  echo "Main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config file containing options"
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --num-epochs <#epochs|15>                        # Number of epochs of training"
  echo "  --initial-learning-rate <initial-learning-rate|0.02> # Learning rate at start of training, e.g. 0.02 for small"
  echo "                                                       # data, 0.01 for large data"
  echo "  --final-learning-rate  <final-learning-rate|0.004>   # Learning rate at end of training, e.g. 0.004 for small"
  echo "                                                   # data, 0.001 for large data"
  echo "  --hidden-layer-dim <hidden-dim|100>           # number of nodes in hidden layer, default 100"
  echo "  --num-hidden-layers <#hidden-layers|2>           # Number of hidden layers, e.g. 2 for 3 hours of data, 4 for 100hrs"
  echo "  --add-layers-period <#iters|2>                   # Number of iterations between adding hidden layers"
  echo "  --num-threads <num-threads|4>                     # Number of parallel jobs to use for main neural net"
  echo "  --minibatch-size <minibatch-size|128>            # Size of minibatch to process (note: product with --num-threads"
  echo "                                                   # should not get too large, e.g. >2k)."
  echo "  --splice-width <width|4>                         # Number of frames on each side to append for feature input"
  echo "                                                   # (note: we splice processed, typically 40-dimensional frames"
  echo "  --lda-dim <dim|250>                              # Dimension to reduce spliced features to with LDA"
  echo "  --stage <stage|-4>                               # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."  
  exit 1;
fi

data_dir=$1
lang_dir=$2
ali_dir=$3
exp_dir=$4

# Check some files from our GMM-HMM system
for f in \
    $data_dir/feats.scp \
    $lang_dir/topo \
    $ali_dir/ali.1.gz \
    $ali_dir/final.mdl \
    $ali_dir/tree \
    $ali_dir/num_jobs;
    do [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

# Set number of leaves
num_leaves=`tree-info $ali_dir/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;

# set up some dirs and parameter definition files
nj=`cat $ali_dir/num_jobs` || exit 1;
echo $nj > $exp_dir/num_jobs
cp $ali_dir/tree $exp_dir/tree
mkdir -p $exp_dir/log


echo ""
echo "########################"
echo "### DATA PREPARATION ###"
echo "########################"


if [ $stage -le -5 ]; then

    echo ""
    echo "###############################"
    echo "### BEGIN GET LDA TRANSFORM ###"
    echo "###############################"

    steps/nnet2/get_lda_simple.sh \
        --cmd "$cmd" \
        --lda-dim $lda_dim \
        --feat-type $feat_type \
        --splice-width $splice_width \
        $data_dir \
        $lang_dir \
        $ali_dir \
        $exp_dir \
        || exit 1;

    # these files should have been written by get_lda.sh
    feat_dim=$(cat $exp_dir/feat_dim) || exit 1;
    lda_dim=$(cat $exp_dir/lda_dim) || exit 1;
    lda_mat=$exp_dir/lda.mat || exit;

    echo ""
    echo "#############################"
    echo "### END GET LDA TRANSFORM ###"
    echo "#############################"
fi



if [ $stage -le -4 ]; then

    echo ""
    echo "###################################"
    echo "### BEGIN GET TRAINING EXAMPLES ###"
    echo "###################################"

    steps/nnet2/get_egs_simple.sh \
        --cmd "$cmd" \
        --feat-type $feat_type \
        --splice-width $splice_width \
        --num-jobs-nnet $num_threads \
        --iters-per-epoch $iters_per_epoch \
        $data_dir \
        $ali_dir \
        $exp_dir \
        || exit 1;

    # this is the path to the new egs dir that was just created
    egs_dir=$exp_dir/egs


    echo ""
    echo "#################################"
    echo "### END GET TRAINING EXAMPLES ###"
    echo "#################################"

fi



if [ $stage -le -3 ]; then

    echo ""
    echo "#####################################"
    echo "### BEGIN INITIALIZING NEURAL NET ###"
    echo "#####################################"

    stddev=`perl -e "print 1.0/sqrt($hidden_layer_dim);"`

    cat >$exp_dir/nnet.config <<EOF
SpliceComponent input-dim=$feat_dim left-context=$splice_width right-context=$splice_width
FixedAffineComponent matrix=$lda_mat
AffineComponent input-dim=$lda_dim output-dim=$hidden_layer_dim learning-rate=$initial_learning_rate param-stddev=$stddev bias-stddev=$bias_stddev
TanhComponent dim=$hidden_layer_dim
AffineComponent input-dim=$hidden_layer_dim output-dim=$num_leaves learning-rate=$initial_learning_rate param-stddev=$stddev bias-stddev=$bias_stddev
SoftmaxComponent dim=$num_leaves
EOF

    # to hidden.config it will write the part of the config corresponding to a
    # single hidden layer; we need this to add new layers. 
    cat >$exp_dir/hidden.config <<EOF
AffineComponent input-dim=$hidden_layer_dim output-dim=$hidden_layer_dim learning-rate=$initial_learning_rate param-stddev=$stddev bias-stddev=$bias_stddev
TanhComponent dim=$hidden_layer_dim
EOF

    $cmd $exp_dir/log/nnet_init.log \
        nnet-am-init \
            $ali_dir/tree \
            $lang_dir/topo \
            "nnet-init $exp_dir/nnet.config -|" \
            $exp_dir/0.mdl \
            || exit 1;

    echo "### TRAIN TRANSITION PROBS AND SET PRIORS ###"

    $cmd $exp_dir/log/train_trans.log \
        nnet-train-transitions \
            $exp_dir/0.mdl \
            "ark:gunzip -c $ali_dir/ali.*.gz|" \
            $exp_dir/0.mdl \
            || exit 1;

    echo ""
    echo "####################################"
    echo "### DONE INITIALIZING NEURAL NET ###"
    echo "####################################"

fi




if [ $stage -le -2 ]; then

    echo ""
    echo "#################################"
    echo "### BEGIN TRAINING NEURAL NET ###"
    echo "#################################"
    
    # get some info on iterations and number of models we're training
    iters_per_epoch=`cat $egs_dir/iters_per_epoch` || exit 1;
    num_jobs_nnet=`cat $egs_dir/num_jobs_nnet` || exit 1;
    num_tot_iters=$[$num_epochs * $iters_per_epoch]

    echo "Will train for $num_epochs epochs = $num_tot_iters iterations"
    
    # Main training loop
    x=0
    while [ $x -lt $num_tot_iters ]; do
            
        echo "Training neural net (pass $x)"
        
        # IF *not* first iteration \
        # AND we still have layers to add \
        # AND its the right time to add a layer
        if [ $x -gt 0 ] \
            && [ $x -le $[($num_hidden_layers-1)*$add_layers_period] ] \
            && [ $[($x-1) % $add_layers_period] -eq 0 ]; 
        then
            echo "Adding new hidden layer"
            mdl="nnet-init --srand=$x $exp_dir/hidden.config - |"
            mdl="$mdl nnet-insert $exp_dir/$x.mdl - - |" 
        else
            # otherwise just use the past model
            mdl=$exp_dir/$x.mdl
        fi
        
        # Shuffle examples and train nets with SGD
        $cmd JOB=1:$num_jobs_nnet $exp_dir/log/train.$x.JOB.log \
            nnet-shuffle-egs \
                --srand=$x \
                ark:$egs_dir/egs.JOB.$[$x%$iters_per_epoch].ark \
                ark:- \| \
            nnet-train-parallel \
                --num-threads=$num_threads \
                --minibatch-size=$minibatch_size \
                --srand=$x \
                "$mdl" \
                ark:- \
                $exp_dir/$[$x+1].JOB.mdl \
                || exit 1;
        
        # Get a list of all the nnets which were run on different jobs
        nnets_list=
        for n in `seq 1 $num_jobs_nnet`; do
            nnets_list="$nnets_list $exp_dir/$[$x+1].$n.mdl"
        done
        
        learning_rate=`perl -e '($x,$n,$i,$f)=@ARGV; print ($x >= $n ? $f : $i*exp($x*log($f/$i)/$n));' $[$x+1] $num_tot_iters $initial_learning_rate $final_learning_rate`;
        
        # Average all SGD-trained models for this iteration
        $cmd $exp_dir/log/average.$x.log \
            nnet-am-average \
                $nnets_list - \| \
            nnet-am-copy \
                --learning-rate=$learning_rate \
                - \
                $exp_dir/$[$x+1].mdl \
                || exit 1;
        
        # on to the next model
        x=$[$x+1]
        
    done;
    
    # copy and rename final model as final.mdl
    cp $exp_dir/$x.mdl $exp_dir/final.mdl
    
    echo ""
    echo "################################"
    echo "### DONE TRAINING NEURAL NET ###"
    echo "################################"
    
fi


sleep 2
