#!/bin/bash

# Joshua Meyer (2017)


# USAGE:
#
#      ./run.sh <corpus_name>
#
# INPUT:
#
#
#
# OUTPUT:
#
# 

cmd="utils/run.pl"
decode_beam=5
decode_lattice_beam=3
decode_max_active_states=200


graph=$1
model=$2
test_dir=$3
suffix=$4
num_jobs=$5

if [ "$#" -ne 5 ]; then
    echo "ERROR: $0"
    echo "USAGE: $0 <graph> <model> <test_dir> <suffix>"
    exit 1
fi





if [ 1 ]; then
    
    printf "\n####================####\n";
    printf "#### BEGIN DECODING ####\n";
    printf "####================####\n\n";
    
    # DECODE WITH TRIPHONES WITH SAT ADJUSTED FEATURES
    
    # steps/decode_fmllr.sh --cmd "$cmd" \
    #     --nj $num_processors \
    #     ${exp_dir}/triphones_lda_mllt_sat/graph \
    #     ${data_dir}/${test_dir} \
    #     "${exp_dir}"'/triphones_lda_mllt_sat/decode_'"${test_dir}" \
    #     $unknown_phone \
    #     $silence_phone \
    #     || exit 1;

    
    # DECODE WITH REGULAR TRIPHONES WITH VANILLA DELTA FEATURES

    printf "\n ### Decoding with $num_jobs jobs  ### "
    
    steps/decode.sh \
        --cmd "$cmd" \
        --nj $num_jobs \
        --beam $decode_beam \
        --lattice-beam $decode_lattice_beam \
        --max-active $decode_max_active_states \
        $graph \
        $model \
        $test_dir \
        $test_dir/decode \
        "SPOKEN_NOISE" \
        "SIL" \
        || printf "\n####\n#### ERROR: decode.sh \n####\n\n" \
        || exit 1;
    

    printf "#### BEGIN CALCULATE WER ####\n";
    
    for x in $test_dir/decode; do
        [ -d $x ] && grep "WER" $x/wer_* | utils/best_wer.sh > WER_triphones_${suffix}.txt;
    done

    printf "\n####==============####\n";
    printf "#### END DECODING ####\n";
    printf "####==============####\n\n";

    echo "###"
    echo "graph = $graph" >> WER_triphones_${suffix}.txt

    echo "###"
    echo "acoustic model = $model" >> WER_triphones_${suffix}.txt
    ../../../src/gmmbin/gmm-info $model >> WER_triphones_${suffix}.txt
    
    echo "###"
    echo "test dir = $test_dir" >> WER_triphones_${suffix}.txt
    
fi

exit;


