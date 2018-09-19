#!/bin/bash

. utils/parse_options.sh
. path.sh

format=svg # pdf or svg
mode=save # display or save
lm_scale=10
acoustic_scale=0.1

if [ $# != 3 ]; then
   echo "usage: $0 [--mode display|save] [--format pdf|svg] <utterance-id> <lattice-ark> <word-list>"
   echo "e.g.:  $0 utt-0001 \"test/lat.*.gz\" tri1/graph/words.txt"
   exit 1;
fi

utterance_id=$1
lattice_file=$2
word_list=$3
tmp_dir=$(mktemp -d /tmp/kaldi.XXXX);


# Extract utterance_id lattice from lattice ark file and convert to FST
# and save new FST in tmp_dir
gunzip -c $lattice_file | \
    lattice-to-fst \
        --lm-scale=$lm_scale \
        --acoustic-scale=$acoustic_scale \
        ark:- "scp,p:echo $utterance_id $tmp_dir/$utterance_id.fst|" \
        || exit 1;

! [ -s $tmp_dir/$utterance_id.fst ] && \
    echo "Failed to extract lattice for utterance $utterance_id (not present?)" \
    && exit 1;


# draw FST and convert to image via dot program
fstdraw --portrait=true \
    --osymbols=$word_list \
    $tmp_dir/$utterance_id.fst | \
    dot -T${format} > ${tmp_dir}/${utterance_id}_lm${lm_scale}_am${acoustic_scale}.${format}


# some if statements relative to native OS
if [ "$(uname)" == "Darwin" ]; then
    doc_open=open

elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    doc_open=xdg-open

elif [ $mode == "display" ] ; then
        echo "Can not automaticaly open file on your operating system"
        mode=save
fi


# save or display new image
[ $mode == "display" ] && \
    $doc_open \
    ${tmp_dir}/${utterance_id}_lm${lm_scale}_am${acoustic_scale}.${format}

[[ $mode == "display" && $? -ne 0 ]] \
    && echo "Failed to open ${format} format." \
    && mode=save

[ $mode == "save" ] \
    && echo "Saving to ${utterance_id}_lm${lm_scale}_am${acoustic_scale}.${format}" \
    && cp ${tmp_dir}/${utterance_id}_lm${lm_scale}_am${acoustic_scale}.${format} .

exit 0
