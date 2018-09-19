#!/bin/bash 

# Copyright 2012  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# To be run from .. (one directory up from here)

# USAGE:
#

#    steps/make_mfcc.sh \
#         data_dir/test_dir \
#         experiment_dir/make_mfcc_log/test_dir \
#         mfcc_dir;

# INPUT:
#
#    /data/{test,train}/
#       wav.scp

# OUTPUT:
#
#    /data/{test,train}/
#       feats.scp
#
#    /mfcc/
#       raw_mfcc_{train,test}.{ark,scp}
# 
#    nb - the feats.scp file comtains a list of paths to the raw_mfcc ark files



mfcc_config=config/mfcc.config
nj=4
cmd="utils/run.pl"

echo "$0 $@"  # Print to the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 3 ]; then
    echo "Usage: $0 [options] <data-dir> <log-dir> <path-to-mfcc_dir> <mfcc-config-dir>";
    echo "e.g.: $0 data/train exp/make_mfcc/train mfcc"
    echo "options: "
    echo "  --mfcc-config <config-file>  # config passed to compute-mfcc-feats "
    echo "  --nj <nj>                                 # number of parallel jobs"
    echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
    exit 1;
fi

###
##
#

data_dir=$1
log_dir=$2
mfcc_dir=$3
scp=$data_dir/wav.scp
compress=true

# make $mfcc_dir an absolute pathname.
mfcc_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $mfcc_dir ${PWD}`
# use "name" as part of name of the archive.
name=`basename $data_dir`

# make model/mfcc
mkdir -p $mfcc_dir || exit 1;
# make model/exp/make_mfcc_log/{train,test}
mkdir -p $log_dir || exit 1;

# if we already have mfccs, don't overwrite them, but save them in
# model/data/.backup/
if [ -f $data_dir/feats.scp ]; then
    mkdir -p $data_dir/.backup
    echo "$0: moving $data_dir/feats.scp to $data_dir/.backup"
    mv $data_dir/feats.scp $data_dir/.backup
fi

# make sure both the wav file paths and the config file are present
# (1) model/data/[train_yesno|test_yesno]/wav.scp
# (2) model/conf/mfcc.config
required="$scp $mfcc_config"
for f in $required; do
    if [ ! -f $f ]; then
        echo "make_mfcc.sh: no such file $f"
        exit 1;
    fi
done
utils/validate_data_dir.sh --no-text --no-feats $data_dir || exit 1;

if [ -f $data_dir/spk2warp ]; then
    echo "$0 [info]: using VTLN warp factors from $data_dir/spk2warp"
    vtln_opts="--vtln-map=ark:$data_dir/spk2warp --utt2spk=ark:$data_dir/utt2spk"
elif [ -f $data_dir/utt2warp ]; then
    echo "$0 [info]: using VTLN warp factors from $data_dir/utt2warp"
    vtln_opts="--vtln-map=ark:$data_dir/utt2warp"
fi

for n in $(seq $nj); do
    # the next command does nothing unless $mfcc_dir/storage/ exists, see
    # utils/create_data_link.pl for more info.
    utils/create_data_link.pl $mfcc_dir/raw_mfcc_$name.$n.ark
done


if [ -f $data_dir/segments ]; then
    echo "$0 [info]: segments file exists: using that."
    
    split_segments=""
    for n in $(seq $nj); do
        split_segments="$split_segments $log_dir/segments.$n"
    done
    
    utils/split_scp.pl $data_dir/segments $split_segments || exit 1;
    rm $log_dir/.error 2>/dev/null
    
    $cmd JOB=1:$nj $log_dir/make_mfcc_${name}.JOB.log \
        extract-segments scp,p:$scp $log_dir/segments.JOB ark:- \| \
        compute-mfcc-feats $vtln_opts --verbose=2 --config=$mfcc_config ark:- ark:- \| \
        copy-feats --compress=$compress ark:- \
        ark,scp:$mfcc_dir/raw_mfcc_$name.JOB.ark,$mfcc_dir/raw_mfcc_$name.JOB.scp \
        || exit 1;
    
else
    echo "$0: [info]: no segments file exists: assuming wav.scp indexed by utterance."
    split_scps=""
    for n in $(seq $nj); do
        split_scps="$split_scps $log_dir/wav_${name}.$n.scp"
    done
    
    utils/split_scp.pl $scp $split_scps || exit 1;
    
    
    # add ,p to the input rspecifier so that we can just skip over
    # utterances that have bad wave data.
    
    $cmd JOB=1:$nj $log_dir/make_mfcc_${name}.JOB.log \
        compute-mfcc-feats $vtln_opts --verbose=2 --config=$mfcc_config \
        scp,p:$log_dir/wav_${name}.JOB.scp ark:- \| \
        copy-feats --compress=$compress ark:- \
        ark,scp:$mfcc_dir/raw_mfcc_$name.JOB.ark,$mfcc_dir/raw_mfcc_$name.JOB.scp \
        || exit 1;
fi


if [ -f $log_dir/.error.$name ]; then
    echo "Error producing mfcc features for $name:"
    tail $log_dir/make_mfcc_${name}.1.log
    exit 1;
fi

# concatenate the .scp files together.
for n in $(seq $nj); do
    cat $mfcc_dir/raw_mfcc_$name.$n.scp || exit 1;
done > $data_dir/feats.scp

rm $log_dir/wav_${name}.*.scp  $log_dir/segments.* 2>/dev/null

nf=`cat $data_dir/feats.scp | wc -l` 
nu=`cat $data_dir/utt2spk | wc -l` 
if [ $nf -ne $nu ]; then
    echo "It seems not all of the feature files were successfully processed ($nf != $nu);"
    echo "consider using utils/fix_data_dir.sh $data_dir"
fi

if [ $nf -lt $[$nu - ($nu/20)] ]; then
    echo "Less than 95% the features were successfully generated.  Probably a serious error."
    exit 1;
fi

printf "Succeeded creating MFCC features for ${name}\n\n"
