#!/bin/bash

# USAGE:
#
# local/prepare_dict.sh \
#    $data_dir \
#    $input_dir \
#    "SIL";

# INPUT:
#
#    input_dir/
#      lexicon_nosil.txt
#      lexicon.txt
#      phones.txt
#
#    "silence_phone"

# OUTPUT:
#
# data_org/
# └── local
#     └── dict
#         ├── lexicon.txt
#         ├── nonsilence_phones.txt
#         ├── optional_silence.txt
#         └── silence_phones.txt



data_dir=$1
input_dir=$2
silence_phone=$3
dict_dir=${data_dir}/local/dict

echo "$0: Creating $dict_dir and moving lexicon files from $input_dir into it."
echo "$0: This script really is just copy-pasting, nothing new generated."

# Creating ./${dict_dir} directory
mkdir -p $dict_dir

# i don't think that lexicon_words.txt is actually ever used
#cp $input_dir/lexicon_nosil.txt $dict_dir/lexicon_words.txt
cp $input_dir/lexicon.txt $dict_dir/lexicon.txt

# cat every non-silence phone from phones.txt into a new file
cat $input_dir/phones.txt | grep -v $silence_phone > $dict_dir/nonsilence_phones.txt

echo $silence_phone > $dict_dir/silence_phones.txt

echo $silence_phone > $dict_dir/optional_silence.txt

printf "Dictionary preparation succeeded\n\n"
