#!/bin/bash

# Given dir of WAV files, create dir for train, create 'wav.scp',
# create 'text', create 'utt2spk' and 'spk2utt'


# USAGE:
#
# local/prepare_data.sh \
#    $audio_dir \
#    $transcripts \
#    $data_dir \
#    $data_type


# INPUT:
#
#    audio_dir/
#
#    transcripts
#

# OUTPUT:

# data_dir/
# │
# └── data_type
#     ├── spk2utt
#     ├── text
#     ├── utt2spk
#     └── wav.scp


audio_dir=$1
transcripts=$2
data_dir=$3
# data_type = train or test
data_type=$4

echo "$0: looking for audio data in $audio_dir"
    
# Make sure we have the audio data (WAV file utterances)
if [ ! -d $audio_dir ]; then
    printf '\n####\n#### ERROR: '"${audio_dir}"' not found \n####\n\n';
    exit 1;
fi


# Creating ./${data_dir} directory
mkdir -p ${data_dir}/local
mkdir -p ${data_dir}/local/tmp

local_dir=${data_dir}/local


###                                                     ###
### Check if utt IDs in transcripts and audio dir match ###
###                                                     ###

ls -1 $audio_dir > $local_dir/tmp/audio.list
awk -F"." '{print $1}' $local_dir/tmp/audio.list > $local_dir/tmp/utt-ids-audio.txt
awk -F" " '{print $1}' $transcripts > $local_dir/tmp/utt-ids-transcripts.txt
for fileName in $local_dir/tmp/utt-ids-audio.txt $local_dir/tmp/utt-ids-transcripts.txt; do
    LC_ALL=C sort -i $fileName -o $fileName;
done;
diff $local_dir/tmp/utt-ids-audio.txt $local_dir/tmp/utt-ids-transcripts.txt > $local_dir/tmp/diff-ids.txt
if [ -s $local_dir/tmp/diff-ids.txt ]; then
    printf "\n####\n#### ERROR: Audio files & transcripts mismatch \n####\n\n";
    printf "\n#### Check the utterance IDs in data_{LANG}/local/tmp/utt-ids-*"
    printf "\n#### and you should find the issue."
    exit 0;
fi



###                                         ###
### Make wav.scp & text & utt2spk & spk2utt ###
###                                         ###

# make two-column lists of utt IDs and path to audio
local/create_wav_scp.pl $audio_dir $local_dir/tmp/audio.list > $local_dir/tmp/${data_type}_wav.scp
# make two-column lists of utt IDs and transcripts
local/create_txt.pl $transcripts $local_dir/tmp/audio.list > $local_dir/tmp/${data_type}.txt

mkdir -p $data_dir/$data_type
# Make wav.scp
cp $data_dir/local/tmp/${data_type}_wav.scp $data_dir/$data_type/wav.scp
# Make text
cp $data_dir/local/tmp/${data_type}.txt $data_dir/$data_type/text
# Make utt2spk
cat $data_dir/$data_type/text | awk '{printf("%s %s\n", $1, $1);}' > $data_dir/$data_type/utt2spk
# Make spk2utt
utils/utt2spk_to_spk2utt.pl <$data_dir/$data_type/utt2spk > $data_dir/$data_type/spk2utt
#clean up temp files
rm -rf $local_dir/tmp



###                 ###
### Print some info ###
###                 ###

## get total number of seconds of WAVs in wav.scp
TOTAL_SECS=0
while IFS='' read -r line || [[ -n "$line" ]]; do
    line=( $line )
    file=${line[1]}
    SECS="$( soxi -D $file )"
    TOTAL_SECS=$( echo "$TOTAL_SECS + $SECS" | bc )
done < "$data_dir/$data_type/wav.scp"

# Calculate hours and print to screen
total_hours=$( echo "scale=2;$TOTAL_SECS / 60 / 60" | bc )
echo ""
echo " $total_hours hours of audio for training "
echo " in $data_dir/$data_type/wav.scp"
echo ""
