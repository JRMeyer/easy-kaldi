#!/bin/bash

# $ ./setup_multitask.sh TO_DIR FROM_DIR "LANG_1 LANG_2 ..."

# langs should be a char string like 'eng eng span'
#
# ASSUMES: file structure for each $lang:
#     
#     data_${lang}/
#                  train/
#                  lang/
#
#     exp_${lang}/
#                  triphones/
#                  triphones_aligned/
#
#
# OUTPUT:

# data
# └── org
#     ├── lang -> ../../data_org/lang/
#     └── train -> ../../data_org/train/
# exp
# └── org
#     ├── mono -> ../../exp_org/monophones
#     ├── mono_ali -> ../../exp_org/monophones_aligned
#     ├── tri -> ../../exp_org/triphones
#     └── tri_ali -> ../../exp_org/triphones_aligned






to_dir=$1
from_dir=$2
langs=$3
langs=( $langs )

for lang in ${langs[@]}; do
    mkdir -p $to_dir/data/$lang $to_dir/exp/$lang;
    
    cd $to_dir/data/$lang;
    ln -s $from_dir/data_${lang}/train/ train
    ln -s $from_dir/data_${lang}/lang/ lang
    
    cd $to_dir/exp/$lang;
    ln -s $from_dir/exp_${lang}/triphones tri
    ln -s $from_dir/exp_${lang}/triphones_aligned tri_ali
    ln -s $from_dir/exp_${lang}/monophones mono
    ln -s $from_dir/exp_${lang}/monophones_aligned mono_ali

done




# langs=$1

# langs=( $langs )

# for lang in ${langs[@]}; do
#     mkdir -p data/$lang exp/$lang;
    
#     cd data/$lang;
#     ln -s ../../data_${lang}/train/ train
#     ln -s ../../data_${lang}/lang/ lang
    
#     cd ../../exp/$lang;
#     ln -s ../../exp_${lang}/triphones tri
#     ln -s ../../exp_${lang}/triphones_aligned tri_ali
#     ln -s ../../exp_${lang}/monophones mono
#     ln -s ../../exp_${lang}/monophones_aligned mono_ali

#     cd ../../
# done


    
