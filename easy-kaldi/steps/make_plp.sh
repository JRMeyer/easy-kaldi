#!/bin/bash

# Copyright 2012-2016  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0
# To be run from .. (one directory up from here)
# see ../run.sh for example

nj=4
cmd=run.pl
plp_config=config/plp.conf
compress=true

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;



if [ $# -ne 3 ]; then
    echo "Usage: $0 [options] <data-dir> [<log-dir> [<plp-dir>] ]";
    echo "e.g.: $0 data/train exp/make_plp/train mfcc"
    echo "Note: <log-dir> defaults to <data-dir>/log, and <plp-dir> defaults to <data-dir>/data"
    echo "Options: "
    echo "  --plp-config <config-file>                      # config passed to compute-plp-feats "
    echo "  --nj <nj>                                        # number of parallel jobs"
    echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
    exit 1;
fi


data_dir=$1
log_dir=$2
plp_dir=$3
scp=$data_dir/wav.scp



for f in $scp $plp_config; do
    if [ ! -f $f ]; then
        echo "$0: no such file $f"
        exit 1;
    fi
done


utils/validate_data_dir.sh --no-text --no-feats $data_dir || exit 1;

# make $plp_dir an absolute pathname.
plp_dir=`perl -e '($dir,$pwd)= @ARGV; if($dir!~m:^/:) { $dir = "$pwd/$dir"; } print $dir; ' $plp_dir ${PWD}`
mkdir -p $plp_dir || exit 1;
mkdir -p $log_dir || exit 1;




if [ -f $data_dir/spk2warp ]; then
    echo "$0 [info]: using VTLN warp factors from $data_dir/spk2warp"
    vtln_opts="--vtln-map=ark:$data_dir/spk2warp --utt2spk=ark:$data_dir/utt2spk"
elif [ -f $data_dir/utt2warp ]; then
    echo "$0 [info]: using VTLN warp factors from $data_dir/utt2warp"
    vtln_opts="--vtln-map=ark:$data_dir/utt2warp"
fi



# use "name" as part of name of the archive.
name=`basename $data_dir`

for n in $(seq $nj); do
    # the next command does nothing unless $plp_dir/storage/ exists, see
    # utils/create_data_link.pl for more info.
    utils/create_data_link.pl $plp_dir/raw_plp_$name.$n.ark
done



if [ -f $data_dir/segments ]; then
    echo "$0 [info]: segments file exists: using that."
    split_segments=""
    for n in $(seq $nj); do
        split_segments="$split_segments $log_dir/segments.$n"
    done
    
    utils/split_scp.pl $data_dir/segments $split_segments || exit 1;
    rm $log_dir/.error 2>/dev/null
    
    $cmd JOB=1:$nj $log_dir/make_plp_${name}.JOB.log \
         extract-segments scp,p:$scp $log_dir/segments.JOB ark:- \| \
         compute-plp-feats $vtln_opts --verbose=2 --config=$plp_config ark:- ark:- \| \
         copy-feats --compress=$compress ark:- \
         ark,scp:$plp_dir/raw_plp_$name.JOB.ark,$plp_dir/raw_plp_$name.JOB.scp \
        || exit 1;
    
else

    echo "$0: [info]: no segments file exists: assuming wav.scp indexed by utterance."

    split_scps=""
    for n in $(seq $nj); do
        split_scps="$split_scps $log_dir/wav_${name}.$n.scp"
    done
    
    utils/split_scp.pl $scp $split_scps || exit 1;
    
    $cmd JOB=1:$nj $log_dir/make_plp_${name}.JOB.log \
         compute-plp-feats \
         $vtln_opts \
         --verbose=2 \
         --config=$plp_config \
         scp,p:$log_dir/wav_${name}.JOB.scp \
         ark:- \| \
         copy-feats \
         --compress=$compress \
         ark:- \
         ark,scp:$plp_dir/raw_plp_$name.JOB.ark,$plp_dir/raw_plp_$name.JOB.scp \
        || exit 1;
    
fi


if [ -f $log_dir/.error.$name ]; then
    echo "Error producing plp features for $name:"
    tail $log_dir/make_plp_${name}.1.log
    exit 1;
fi


# concatenate the .scp files together.
for n in $(seq $nj); do
    cat $plp_dir/raw_plp_$name.$n.scp || exit 1;
done > $data_dir/feats.scp


rm $log_dir/wav_${name}.*.scp  $log_dir/segments.* 2>/dev/null

num_feats=`cat $data_dir/feats.scp | wc -l`
num_utts=`cat $data_dir/utt2spk | wc -l`

if [ $num_feats -ne $num_utts ]; then
    echo "It seems not all of the feature files were successfully ($num_featsf != $num_utts);"
    echo "consider using utils/fix_data_dir.sh $data_dir"
fi
if [ $num_feats -lt $[$num_utts - ($num_utts/20)] ]; then
    echo "Less than 95% the features were successfully generated.  Probably a serious error."
    exit 1;
fi

echo "Succeeded creating PLP features for $name"
