#!/bin/bash

# Joshua Meyer (2017)


# USAGE:
#
#      ./run.sh <corpus_name>
#
# INPUT:
#
#    input_dir/
#       lexicon.txt
#       lexicon_nosil.txt
#       phones.txt
#       task.arpabo
#       transcripts
#
#       audio_dir/
#          utterance1.wav
#          utterance2.wav
#          utterance3.wav
#               .
#               .
#          utteranceN.wav
#
#    config_dir/
#       mfcc.conf
#       topo_orig.proto
#
#
# OUTPUT:
#
#    exp_dir
#    feat_dir
#    data_dir
# 



cmd=utils/run.pl
train_monophones=1
train_triphones=1
adapt_models=0
save_model=0




if [ "$#" -ne 8 ]; then
    echo "ERROR: $0"
    echo "missing args"
    exit 1
fi



data_dir=$1
num_iters_mono=$2
tot_gauss_mono=$3
num_iters_tri=$4
tot_gauss_tri=$5
num_leaves_tri=$6
exp_dir=$7
num_processors=$8



if [ "$train_monophones" -eq "1" ]; then

    printf "\n####===========================####\n";
    printf "#### BEGIN TRAINING MONOPHONES ####\n";
    printf "####===========================####\n\n";

    printf "#### Train Monophones ####\n";

    steps/train_mono.sh \
        --cmd "$cmd" \
        --nj $num_processors \
        --num-iters $num_iters_mono \
        --totgauss $tot_gauss_mono \
        --beam 6 \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/monophones \
        || printf "\n####\n#### ERROR: train_mono.sh \n####\n\n" \
        || exit 1;

    ../../../src/gmmbin/gmm-info ${exp_dir}/monophones/final.mdl


    printf "#### Align Monophones ####\n";

    steps/align_si.sh \
        --cmd "$cmd" \
        --nj $num_processors \
        --boost-silence 1.25 \
        --beam 10 \
        --retry-beam 40 \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/monophones \
        ${exp_dir}/monophones_aligned \
        || printf "\n####\n#### ERROR: align_si.sh \n####\n\n" \
        || exit 1;

    
    printf "\n####===========================####\n";
    printf "#### END TRAINING MONOPHONES ####\n";
    printf "####===========================####\n\n";

fi



if [ "$train_triphones" -eq "1" ]; then

    printf "\n####==========================####\n";
    printf "#### BEGIN TRAINING TRIPHONES ####\n";
    printf "####==========================####\n\n";


    printf "### Train Triphones ###\n"

    steps/train_deltas.sh \
        --cmd "$cmd" \
        --num-iters $num_iters_tri \
        --beam 10 \
        $num_leaves_tri \
        $tot_gauss_tri \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/monophones_aligned \
        ${exp_dir}/triphones \
        || printf "\n####\n#### ERROR: train_deltas.sh \n####\n\n" \
        || exit 1;

    ../../../src/gmmbin/gmm-info ${exp_dir}/triphones/final.mdl


    printf "### Align Triphones ###\n"

    steps/align_si.sh \
        --cmd "$cmd" \
        --nj $num_processors \
        --boost-silence 1.25 \
        --beam 10 \
        --retry-beam 40 \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/triphones \
        ${exp_dir}/triphones_aligned \
        || printf "\n####\n#### ERROR: align_si.sh \n####\n\n" \
        || exit 1;

    
    printf "\n####========================####\n";
    printf "#### END TRAINING TRIPHONES ####\n";
    printf "####========================####\n\n";

fi




if [ "$adapt_models" -eq "1" ]; then
    
    printf "\n####==========================####\n";
    printf "#### BEGIN SPEAKER ADAPTATION ####\n";
    printf "####==========================####\n\n";

    printf "### Begin LDA + MLLT Triphones ###\n"

    steps/train_lda_mllt.sh \
        --cmd "$cmd" \
        --splice-opts "--left-context=3 --right-context=3" \
        $num_leaves_tri \
        $tot_gauss_tri \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/triphones_aligned \
        ${exp_dir}/triphones_lda_mllt \
        || printf "\n####\n#### ERROR: train_lda_mllt.sh \n####\n\n" \
        || exit 1;

    ../../../src/gmmbin/gmm-info ${exp_dir}/triphones_lda_mllt/final.mdl


    printf "### Align LDA + MLLT Triphones ###\n"

    steps/align_si.sh \
        --cmd "$cmd" \
        --nj $num_processors \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/triphones_lda_mllt \
        ${exp_dir}/triphones_lda_mllt_aligned \
        || printf "\n####\n#### ERROR: align_si.sh \n####\n\n" \
        || exit 1;



    printf "\n####===========================####\n";
    printf "#### BEGIN TRAINING SAT (fMLLR) ####\n";
    printf "####============================####\n\n";


    printf "### Train LDA + MLLT + SAT Triphones ###\n"

    steps/train_sat.sh \
        --cmd "$cmd" \
        $num_leaves_tri \
        $tot_gauss_tri \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/triphones_lda_mllt_aligned \
        ${exp_dir}/triphones_lda_mllt_sat \
        || printf "\n####\n#### ERROR: train_sat.sh \n####\n\n" \
        || exit 1;

    ../../../src/gmmbin/gmm-info ${exp_dir}/triphones_lda_mllt_sat/final.mdl


    printf "### Align LDA + MLLT + SAT Triphones ###\n"

    steps/align_fmllr.sh \
        --cmd "$cmd" \
        --nj $num_processors \
        ${data_dir}/train \
        ${data_dir}/lang \
        ${exp_dir}/triphones_lda_mllt_sat \
        ${exp_dir}/triphones_lda_mllt_sat_aligned \
        || printf "\n####\n#### ERROR: align_si.sh \n####\n\n" \
        || exit 1;
fi




if [ "$save_model" -eq "1" ]; then

    # Copy all necessary files to use new LM with this acoustic model
    # and only necessary files to save space
    
    cp data_${corpus_name} ${corpus_name}_${run}

    # delete unneeded files
    rm -rf ${corpus_name}_${run}/train ${corpus_name}_${run}/test ${corpus_name}_${run}/lang_decode

    # copy acoustic model and decision tree to new dir
    mkdir ${corpus_name}_${run}/model
    cp exp_${corpus_name}/triphones/final.mdl ${corpus_name}_${run}/model/final.mdl
    cp exp_${corpus_name}/triphones/tree ${corpus_name}_${run}/model/tree

    tar -zcvf ${corpus_name}_${run}.tar.gz ${corpus_name}_${run}

    # clean up
    rm -rf ${corpus_name}_${run}

    # move for storage
    mkdir compressed_experiments
    
    mv ${corpus_name}_${run}.tar.gz compressed_experiments/${corpus_name}_${run}.tar.gz
fi




exit;


