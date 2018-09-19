#!/bin/bash

# given an alignment ark file, return
# <utt-id> <trans-id> <start_frame> <end_frame>


ali_ark_file=$1
feats_ark_file=$2

. ./path.sh


if [ "$#" -ne "2" ]; then
    echo " ERROR $0: wrong number of args"
    exit 1;
fi


echo "$0: assuming $1 is a compressed alignments file"
# returns a file like this:
# utt-id 1 1 1 45 45 45 600 600 600 600 7 7 7
gunzip -c $ali_ark_file > ali.txt



echo "#########################"
echo "### FORMAT ALIGNMENTS ###"
echo "#########################"

while read line; do

    # get length of alignment
    myarr=($line)
    len=${#myarr[@]}

    # set some counters
    index=0
    cur_id=''
    old_id=''
    frame_i=0
    frame_j=0

    # looping over the transitionID-to-frame level alignments
    for i in $line; do

        cur_id=$i

        if [ "$index" -eq "0" ]; then
            # utt-id
            utt_id=$i
            ((index++))
        elif [ "$index" -eq "1" ]; then
            old_id=$i
            ((index++))
        elif [ "$cur_id" -eq "$old_id" ]; then
             # repeat trans-id
            ((index++))
        else
            # cur_id is not the same as old_id
            frame_j=$((index-1))
            echo "$old_id $utt_id $frame_i $frame_j" >> all_segments.txt
            # reset for next id
            old_id=$cur_id
            frame_i=$((index-1))
            ((index++))
        fi
        
        if [ "$index" -eq "$len" ] ; then
            # the last frame, we need to add one to length for extract-rows
            frame_j=$((frame_j+1))
            echo "$old_id $utt_id $frame_i $frame_j" >> all_segments.txt
        fi        
    done;

done<ali.txt
rm ali.txt




echo "### SPLIT ALIs FOR MULTIPLE JOBS ###"

num_lines=(`wc -l all_segments.txt`)
num_processors=(`nproc`)
segs_per_job=$(( num_lines / num_processors ))

echo "$0: processing $num_lines segments from $ali_ark_file"
echo "$0: splitting segments over $num_processors CPUs"
echo "$0: with $segs_per_job segments per job."
# will split into segments00 segments01 ... etc
split -l $segs_per_job --numeric-suffixes --additional-suffix=.tmp all_segments.txt segments_split
rm all_segments.txt




echo "#################################"
echo "### EXTRACT FRAMES FROM FEATS ###"
echo "#################################"

# make an array for proc ids
proc_ids=()

for i in segments_split*.tmp; do
    echo "$0: Extracting $i from $feats_ark_file and saving to $segments_and_frames_${i}"
    touch segments_and_frames_${i}
    # extract the alignments from the original ark_file and save to outfile
    extract-rows $i ark:$feats_ark_file ark,t:segments_and_frames_${i} & 
    proc_ids+=($!)
done
# wait for subprocesses to stop
for proc_id in ${proc_ids[*]}; do wait $proc_id; done;
rm segments_split*.tmp



echo "### REFORMAT to get <LABEL> <DATA>\n ###"

trans_id=''
frame=''
proc_ids=()

for segs in segments_and_frames_*; do 

    while read line; do
        if `echo $line | grep -q "\["` ; then
            i=($line);
            trans_id=${i[0]};        
        elif `echo $line | grep -q "\]"`; then
            i=($line);
            unset "i[${#i[@]}-1]";
            frame="${i[@]}";
            echo "$trans_id $frame" >> tmp_${segs};
        else
            frame=$line;
            echo "$trans_id $frame" >> tmp_${segs};
        fi;
        
    done<$segs &
    proc_ids+=($!)
done
# wait for subprocesses to stop
for proc_id in ${proc_ids[*]}; do wait $proc_id; done;
rm segments_and_frames_*

cat tmp_segments* >> labeled_frames.txt
echo "$0: DONE! Find your labeled data in labeled_frames.txt"
echo "$0: now you can use ./extract_sub_train_labels.sh on labeled_frames.txt"
rm tmp_segments*
