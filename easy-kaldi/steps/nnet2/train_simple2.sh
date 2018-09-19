#!/bin/bash

# Copyright 2012-2014  Johns Hopkins University (Author: Daniel Povey).
#                2013  Xiaohui Zhang
#                2013  Guoguo Chen
#                2014  Vimal Manohar
# Apache 2.0.


# train_pnorm_simple2.sh is as train_pnorm_simple.sh but it uses the "new" egs
# format, created by get_egs2.sh.

# train_pnorm_simple.sh is a modified version of train_pnorm_fast.sh.  Like
# train_pnorm_fast.sh, it uses the `online' preconditioning, which is faster
# (especially on GPUs).  The difference is that the learning-rate schedule is
# simpler, with the learning rate exponentially decreasing during training,
# and no phase where the learning rate is constant.
#
# Also, the final model-combination is done a bit differently: we combine models
# over typically a whole epoch, and because that would be too many iterations to
# easily be able to combine over, we arrange the iterations into groups (20
# groups by default) and average over each group.
#

# Begin configuration section.
cmd=run.pl
num_epochs=15      # Number of epochs of training;
                   # the number of iterations is worked out from this.
initial_learning_rate=0.04
final_learning_rate=0.004
bias_stddev=0.5

minibatch_size=128 # by default use a smallish minibatch size for neural net
                   # training; this controls instability which would otherwise
                   # be a problem with multi-threaded update.

samples_per_iter=400000 # each iteration of training, see this many samples
                        # per job.  This option is passed to get_egs2.sh
num_jobs_nnet=4    # Number of neural net jobs to run in parallel.  This option
                   # is passed to get_egs.sh.
prior_subset_size=10000 # 10k samples per job, for computing priors.  Should be
                        # more than enough.
num_jobs_compute_prior=10 # these are single-threaded, run on CPU.
get_egs_stage=0
hidden_layer_dim=50

max_models_combine=20 # The "max_models_combine" is the maximum number of models we give
  # to the final 'combine' stage, but these models will themselves be averages of
  # iteration-number ranges.

shuffle_buffer_size=500 # This "buffer_size" variable controls randomization of the samples
                # on each iter.  You could set it to 0 or to a large value for complete
                # randomization, but this would both consume memory and cause spikes in
                # disk I/O.  Smaller is easier on disk and memory but less random.  It's
                # not a huge deal though, as samples are anyway randomized right at the start.
                # (the point of this is to get data in different minibatches on different iterations,
                # since in the preconditioning method, 2 samples in the same minibatch can
                # affect each others' gradients.

add_layers_period=2 # by default, add new layers every 2 iterations.
num_hidden_layers=2
stage=-4

splice_width=2 # meaning +- 4 frames on each side for second LDA
left_context= # if set, overrides splice-width
right_context= # if set, overrides splice-width.
randprune=4.0 # speeds up LDA.
max_change_per_sample=0.075

mix_up=0 # Number of components to mix up to (should be > #tree leaves, if
        # specified.)
num_threads=16
parallel_opts="--num-threads 16 --mem 1G"
  # by default we use 16 threads; this lets the queue know.
  # note: parallel_opts doesn't automatically get adjusted if you adjust num-threads.
combine_num_threads=8
combine_parallel_opts="--num-threads 8"  # queue options for the "combine" stage.
cleanup=true
lda_opts=
lda_dim=
transform_dir=     # If supplied, overrides alidir
feat_type=  # Can be used to force "raw" features.
# End configuration section.


echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

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
  echo "  --num-hidden-layers <#hidden-layers|2>           # Number of hidden layers, e.g. 2 for 3 hours of data, 4 for 100hrs"
  echo "  --add-layers-period <#iters|2>                   # Number of iterations between adding hidden layers"
  echo "  --num-jobs-nnet <num-jobs|8>                     # Number of parallel jobs to use for main neural net"
  echo "                                                   # training (will affect results as well as speed; try 8, 16)"
  echo "                                                   # Note: if you increase this, you may want to also increase"
  echo "                                                   # the learning rate."
  echo "  --num-threads <num-threads|16>                   # Number of parallel threads per job (will affect results"
  echo "                                                   # as well as speed; may interact with batch size; if you increase"
  echo "                                                   # this, you may want to decrease the batch size."
  echo "  --parallel-opts <opts|\"--num-threads 16 --mem 1G\">      # extra options to pass to e.g. queue.pl for processes that"
  echo "                                                   # use multiple threads... "
  echo "  --io-opts <opts|\"--max-jobs-run 10\">                      # Options given to e.g. queue.pl for jobs that do a lot of I/O."
  echo "  --minibatch-size <minibatch-size|128>            # Size of minibatch to process (note: product with --num-threads"
  echo "                                                   # should not get too large, e.g. >2k)."
  echo "  --samples-per-iter <#samples|400000>             # Number of samples of data to process per iteration, per"
  echo "                                                   # process."
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
dir=$4

# Check some files.
for f in $data_dir/feats.scp \
             $lang_dir/L.fst \
             $ali_dir/ali.1.gz \
             $ali_dir/final.mdl \
             $ali_dir/tree; do
    [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

# Set number of leaves
num_leaves=`tree-info $ali_dir/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1

# set up some dirs and parameter definition files
nj=`cat $ali_dir/num_jobs` || exit 1;
echo $nj > $exp_dir/num_jobs
cp $ali_dir/tree $exp_dir
mkdir -p $exp_dir/log


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

    echo "$0: calling get_egs2.sh"
    
    steps/nnet2/get_egs2.sh \
        --samples-per-iter $samples_per_iter \
        --stage $get_egs_stage \
        --cmd "$cmd" \
        $data_dir \
        $ali_dir \
        $exp_dir/egs \
        || exit 1;

    frames_per_eg=$(cat $exp_dir/egs/info/frames_per_eg)
    num_archives=$(cat $exp_dir/egs/info/num_archives)
    # num_archives_expanded considers each separate label-position from
    # 0..frames_per_eg-1 to be a separate archive.
    num_archives_expanded=$[$num_archives*$frames_per_eg]

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

    lda_mat=$exp_dir/lda.mat
    tot_input_dim=$[$feat_dim]

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

    ## WHAT IS THIS FOR???
    # obtains raw pdf count
    $cmd JOB=1:$nj $exp_dir/log/acc_pdf.JOB.log \
         ali-to-post \
         "ark:gunzip -c $ali_dir/ali.JOB.gz|" \
         ark:- \| \
         post-to-tacc \
         --per-pdf=true \
         --binary=false \
         $ali_dir/final.mdl \
         ark:- \
         $exp_dir/JOB.pacc \
        || exit 1;

    cat $exp_dir/*.pacc > $exp_dir/pacc
    rm $exp_dir/*.pacc

fi
fi

# set num_iters so that as close as possible, we process the data $num_epochs
# times, i.e. $num_iters*$num_jobs_nnet == $num_epochs*$num_archives_expanded
num_iters=$[($num_epochs*$num_archives_expanded)/$num_jobs_nnet]

echo "$0: Will train for $num_epochs epochs = $num_iters iterations"
echo "$0: Will not do mix up"

finish_add_layers_iter=$[$num_hidden_layers * $add_layers_period]
# This is when we decide to mix up from: halfway between when we've finished
# adding the hidden layers and the end of training.
mix_up_iter=$[($num_iters + $finish_add_layers_iter)/2]
 

approx_iters_per_epoch=$[$num_iters/$num_epochs]
# First work out how many models we want to combine over in the final
# nnet-combine-fast invocation.  This equals
# min(max(max_models_combine, iters_per_epoch),
#     2/3 * iters_after_mixup)
num_models_combine=$max_models_combine

if [ $num_models_combine -lt $approx_iters_per_epoch ]; then
    num_models_combine=$approx_iters_per_epoch
fi

iters_after_mixup_23=$[(($num_iters-$mix_up_iter-1)*2)/3]
if [ $num_models_combine -gt $iters_after_mixup_23 ]; then
    num_models_combine=$iters_after_mixup_23
fi

first_model_combine=$[$num_iters-$num_models_combine+1]

x=0
cur_egs_dir=$egs_dir

while [ $x -lt $num_iters ];do

    prev_egs_dir=$cur_egs_dir
    cur_egs_dir=$exp_dir/egs_$x
    
    if [ $x -ge 0 ] && [ $stage -le $x ]; then
        
        echo "Training neural net (pass $x)"
        
        # IF *not* first iteration \
        # AND we still have layers to add \
        # AND its the right time to add a layer
        if [ $x -gt 0 ] \
               && [ $x -le $[($num_hidden_layers-1)*$add_layers_period] ] \
               && [ $[($x-1) % $add_layers_period] -eq 0 ]; 
        then
            echo "Adding new hidden layer"
            inp=`nnet-am-info $exp_dir/$x.mdl | grep 'Softmax' | awk '{print $2}'`
            inp=$[$inp-1]
            
            mdl="nnet-init --srand=$x $exp_dir/hidden.config - | nnet-insert --insert-at=$inp $exp_dir/$x.mdl - - |"
        else
            # otherwise just use the past model
            mdl=$exp_dir/$x.mdl
        fi
        
        
        rm $exp_dir/.error 2>/dev/null
        
        ## SHUFFLE EGS AND TRAIN NNET
        
        # We can't easily use a single parallel SGE job to do the main training,
        # because the computation of which archive and which --frame option
        # to use for each job is a little complex, so we spawn each one separately.
        
        for n in $(seq $num_jobs_nnet); do
            # k is a zero-based index that we'll derive the other indexes from.
            k=$[$x*$num_jobs_nnet + $n - 1];
            # work out the 1-based archive index.
            archive=$[($k%$num_archives)+1];
            # work out the 0-based frame index; this increases more slowly than the
            # archive index because the same archive with different frame indexes
            # will give similar gradients, so we want to separate them in time.
            frame=$[(($k/$num_archives)%$frames_per_eg)];
            
            
            $cmd $parallel_opts $exp_dir/log/train.$x.$n.log \
                 nnet-train-parallel \
                 $parallel_train_opts \
                 --minibatch-size=$this_minibatch_size \
                 --srand=$x "$mdl" \
                 "ark,bg:nnet-copy-egs --frame=$frame ark:$cur_egs_dir/egs.$archive.ark ark:-|nnet-shuffle-egs --srand=$x ark:- ark:-|" \
                 $exp_dir/$[$x+1].$n.mdl \
                || touch $exp_dir/.error &
        done
        
        nnets_list=
        for n in `seq 1 $num_jobs_nnet`; do
            nnets_list="$nnets_list $exp_dir/$[$x+1].$n.mdl"
        done
        
        learning_rate=`perl -e '($x,$n,$i,$f)=@ARGV; print ($x >= $n ? $f : $i*exp($x*log($f/$i)/$n));' $[$x+1] $num_iters $initial_learning_rate $final_learning_rate`;
        
        # Average all SGD-trained models for this iteration
        $cmd $exp_dir/log/average.$x.log \
             nnet-am-average \
             $nnets_list - \| \
             nnet-am-copy \
             --learning-rate=$learning_rate \
             - \
             $exp_dir/$[$x+1].mdl \
            || exit 1;
        
    fi
    x=$[$x+1]
done


if [ $stage -le $num_iters ]; then
    echo "Doing final combination to produce final.mdl"
    
    # Now do combination.
    nnets_list=()
    # the if..else..fi statement below sets 'nnets_list'.
    if [ $max_models_combine -lt $num_models_combine ]; then
        # The number of models to combine is too large, e.g. > 20.  In this case,
        # each argument to nnet-combine-fast will be an average of multiple models.
        cur_offset=0 # current offset from first_model_combine.
        for n in $(seq $max_models_combine); do
            next_offset=$[($n*$num_models_combine)/$max_models_combine]
            sub_list=""
            for o in $(seq $cur_offset $[$next_offset-1]); do
                iter=$[$first_model_combine+$o]
                mdl=$exp_dir/$iter.mdl
                [ ! -f $mdl ] && echo "Expected $mdl to exist" && exit 1;
                sub_list="$sub_list $mdl"
            done
            nnets_list[$[$n-1]]="nnet-am-average $sub_list - |"
            cur_offset=$next_offset
        done
    else
        nnets_list=
        for n in $(seq 0 $[num_models_combine-1]); do
            iter=$[$first_model_combine+$n]
            mdl=$exp_dir/$iter.mdl
            [ ! -f $mdl ] && echo "Expected $mdl to exist" && exit 1;
            nnets_list[$n]=$mdl
        done
    fi
    
    
    # Below, use --use-gpu=no to disable nnet-combine-fast from using a GPU, as
    # if there are many models it can give out-of-memory error; set num-threads to 8
    # to speed it up (this isn't ideal...)
    num_egs=`nnet-copy-egs ark:$cur_egs_dir/combine.egs ark:/dev/null 2>&1 | tail -n 1 | awk '{print $NF}'`
    mb=$[($num_egs+$combine_num_threads-1)/$combine_num_threads]
    [ $mb -gt 512 ] && mb=512
    # Setting --initial-model to a large value makes it initialize the combination
    # with the average of all the models.  It's important not to start with a
    # single model, or, due to the invariance to scaling that these nonlinearities
    # give us, we get zero diagonal entries in the fisher matrix that
    # nnet-combine-fast uses for scaling, which after flooring and inversion, has
    # the effect that the initial model chosen gets much higher learning rates
    # than the others.  This prevents the optimization from working well.
    $cmd $combine_parallel_opts $exp_dir/log/combine.log \
         nnet-combine-fast --initial-model=100000 --num-lbfgs-iters=40 --use-gpu=no \
         --num-threads=$combine_num_threads \
         --verbose=3 --minibatch-size=$mb "${nnets_list[@]}" ark:$cur_egs_dir/combine.egs \
         $exp_dir/final.mdl || exit 1;
    
    
    # Compute the probability of the final, combined model with
    # the same subset we used for the previous compute_probs, as the
    # different subsets will lead to different probs.
    $cmd $exp_dir/log/compute_prob_valid.final.log \
         nnet-compute-prob $exp_dir/final.mdl ark:$cur_egs_dir/valid_diagnostic.egs &
    $cmd $exp_dir/log/compute_prob_train.final.log \
         nnet-compute-prob $exp_dir/final.mdl ark:$cur_egs_dir/train_diagnostic.egs &
fi

if [ $stage -le $[$num_iters+1] ]; then
    echo "Getting average posterior for purposes of adjusting the priors."
    # Note: this just uses CPUs, using a smallish subset of data.
    rm $exp_dir/post.$x.*.vec 2>/dev/null
    $cmd JOB=1:$num_jobs_compute_prior $exp_dir/log/get_post.$x.JOB.log \
         nnet-copy-egs --frame=random --srand=JOB ark:$cur_egs_dir/egs.1.ark ark:- \| \
         nnet-subset-egs --srand=JOB --n=$prior_subset_size ark:- ark:- \| \
         nnet-compute-from-egs "nnet-to-raw-nnet $exp_dir/final.mdl -|" ark:- ark:- \| \
         matrix-sum-rows ark:- ark:- \| vector-sum ark:- $exp_dir/post.$x.JOB.vec || exit 1;
    
    sleep 3;  # make sure there is time for $exp_dir/post.$x.*.vec to appear.
    
    $cmd $exp_dir/log/vector_sum.$x.log \
         vector-sum $exp_dir/post.$x.*.vec $exp_dir/post.$x.vec || exit 1;
    
    rm $exp_dir/post.$x.*.vec;
    
    echo "Re-adjusting priors based on computed posteriors"
    $cmd $exp_dir/log/adjust_priors.final.log \
         nnet-adjust-priors $exp_dir/final.mdl $exp_dir/post.$x.vec $exp_dir/final.mdl || exit 1;
fi


if [ ! -f $exp_dir/final.mdl ]; then
    echo "$0: $exp_dir/final.mdl does not exist."
    # we don't want to clean up if the training didn't succeed.
    exit 1;
fi

sleep 2

echo Done

if $cleanup; then
    echo Cleaning up data
    if [[ $cur_egs_dir =~ $exp_dir/egs* ]]; then
        steps/nnet2/remove_egs.sh $cur_egs_dir
    fi
    
    echo Removing most of the models
    for x in `seq 0 $num_iters`; do
        if [ $[$x%100] -ne 0 ] && [ $x -ne $num_iters ] && [ -f $exp_dir/$x.mdl ]; then
            # delete all but every 100th model; don't delete the ones which combine to form the final model.
            rm $exp_dir/$x.mdl
        fi
    done
fi
