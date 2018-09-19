#!/bin/bash

# Joshua Meyer (2017)


# USAGE:
#
# 
# INPUT:
#
#


input_dir=$1
data_dir=$2


if [ "$#" -ne 2 ]; then
    echo "ERROR: $0"
    echo "USAGE: $0 <input_dir> <data_dir>"
    exit 1
fi


echo "$0: Looking for lexicon files in $input_dir"

for i in lexicon.txt lexicon_nosil.txt; do
    LC_ALL=C sort -i $input_dir/$i -o $input_dir/$i;
done;


echo "$0: Extracting phonemes from $input_dir/lexicon.txt and saving them to $input_dir/phones.txt"
cut -d' ' -f2- $input_dir/lexicon.txt | grep -o -E '\w+' | LC_ALL=C sort -u > $input_dir/phones.txt


# move lexicon files
local/prepare_dict.sh \
    $data_dir \
    $input_dir \
    "SIL" \
    || printf "\n####\n#### ERROR: prepare_dict.sh\n####\n\n" \
    || exit 1;

# create L.fst
local/prepare_lang.sh \
    --position-dependent-phones false \
    $data_dir/local/dict \
    $data_dir/local/lang \
    $data_dir/lang \
    "<unk>" \
    || printf "\n####\n#### ERROR: prepare_lang.sh\n####\n\n" \
    || exit 1;




exit;


