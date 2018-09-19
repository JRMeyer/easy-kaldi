#!/bin/bash

# This file takes in 3 inputs, the feats file, segments file
# with lists of segments to be extrated, and the output file

bin_ark_feats=$1
out_file=$2


if [ "$#" -ne 2 ]; then
    echo "$0: Illegal number of parameters";
    exit 1;
fi


. ./path.sh

# this is the form of the segments file I need, and I can get all the
# relevant info from the *.ali files

# segment_name utt-id frame_i frame_j
# echo "transition-123 org_atai_02 25 30" >> segments_file.txt
# echo "transition-123 org_atai_02 56 57" >> segments_file.txt
# echo "transition-001 org_atai_02 2 4" >> segments_file.txt

# get the segments file:

# gunzip -c ali.1.gz > 1.ali

# returns a file like this:
#
# utt-id 1 1 1 45 45 45 600 600 600 600 7 7 7 

for trans_id in feats_ark

extract-rows segments_file.txt ark:$bin_ark_feats ark,t:$out_file
