#!/bin/bash

# Joshua Meyer (2017)


# USAGE:
#
#
# INPUT:
#
#
# OUTPUT:
#


data_dir=$1
exp_dir=$2


if [ "$#" -ne 2 ]; then
    echo "ERROR: $0"
    echo "USAGE: $0 <data_dir> <exp_dir>"
    exit 1
fi




printf "\n####=========================####\n";
printf "#### BEGIN GRAPH COMPILATION ####\n";
printf "####=========================####\n\n";

# Graph compilation

# This script creates a fully expanded decoding graph (HCLG) that represents
# the language-model, pronunciation dictionary (lexicon), context-dependency,
# and HMM structure in our model.  The output is a Finite State Transducer
# that has word-ids on the output, and pdf-ids on the input (these are indexes
# that resolve to Gaussian Mixture Models).

# echo "### Compile monophone graph in ${exp_dir}/monophones/graph"

# utils/mkgraph.sh \
#     --mono \
#     ${data_dir}/lang_decode \
#     ${exp_dir}/monophones \
#     ${exp_dir}/monophones/graph \
#     || printf "\n####\n#### ERROR: mkgraph.sh \n####\n\n" \
#     || exit 1;

echo "### Compile triphone graph in ${exp_dir}/triphones/graph"


utils/mkgraph.sh \
    $input_dir \
    $data_dir \
    $data_dir/lang_decode \
    $exp_dir/triphones \
    $exp_dir/triphones/graph \
    || printf "\n####\n#### ERROR: mkgraph.sh \n####\n\n" \
    || exit 1;

printf "\n####=======================####\n";
printf "#### END GRAPH COMPILATION ####\n";
printf "####=======================####\n\n";


exit;


