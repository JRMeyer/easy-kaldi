llengua=$1
input_dir=$2
audio_dir=$input_dir/audio
transcripts=$input_dir/transcripts
local_dir=/tmp/$llengua
data_dir=$local_dir/train
log_dir=$local_dir/log

#+ bash -x local/prepare_audio_data.sh input_chv/audio input_chv/transcripts data_chv train
###############################################################################

mkdir -p $local_dir
mkdir -p $log_dir
mkdir -p $data_dir

ls -1 $audio_dir > /tmp/$llengua/audio.list
cat $local_dir/audio.list | sed 's/\.wav$//g' | LC_ALL=C sort -i > $local_dir/utt-ids-audio.txt
cat $transcripts | cut -f1 | LC_ALL=C sort -i > $local_dir/utt-ids-transcripts.txt
diff $local_dir/utt-ids-audio.txt $local_dir/utt-ids-transcripts.txt > $local_dir/diff-ids.txt

if [[ -s $local_dir/diff-ids.txt ]]; then
	printf "\n#### ERROR: Audio files & transcripts mismatch \n####\n";
	exit 0;
else
	printf "Audio and transcripts aligned...\n";	
fi

###############################################################################

mkdir -p $data_dir

local/create_wav_scp.pl $audio_dir $local_dir/audio.list > $data_dir/wav.scp
local/create_txt.pl $transcripts $local_dir/audio.list > $data_dir/text
cat $data_dir/text | awk '{printf("%s %s\n", $1, $1);}' > $data_dir/utt2spk
cat $data_dir/utt2spk | utils/utt2spk_to_spk2utt.pl > $data_dir/spk2utt

###############################################################################

TOTAL_SECS=0
while IFS='' read -r line || [[ -n "$line" ]]; do
    line=( $line )
    file=${line[1]}
    SECS="$( soxi -D $file )"
    TOTAL_SECS=$( echo "$TOTAL_SECS + $SECS" | bc )
done < "$data_dir/wav.scp"

total_hours=$(date -u -d @"$TOTAL_SECS" +"%T")
echo ""
echo "$total_hours of audio for training in $data_dir/wav.scp"
echo ""

#+ bash -x ./extract_feats.sh data_chv/train plp_chv 4
#++ steps/make_plp.sh \
###############################################################################

plp_config=config/plp.conf
compress=true
plp_dir=$local_dir/plp

mkdir -p $plp_dir

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

for i in spk2utt text utt2spk wav.scp; do
    LC_ALL=C sort -i $data_dir/$i -o $data_dir/$i;
done

utils/validate_data_dir.sh --no-text --no-feats $data_dir || exit 1;

name=`basename $data_dir`

split_scps=""
for n in `seq 1`; do
	split_scps="$split_scps $log_dir/wav_${name}.$n.scp"
done
    
utils/split_scp.pl $data_dir/wav.scp $split_scps || exit 1;

utils/run.pl JOB=1 $log_dir/make_plp_${name}.JOB.log \
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

if [ -f $log_dir/.error.$name ]; then
    echo "Error producing plp features for $name:"
    tail $log_dir/make_plp_${name}.1.log
    exit 1;
fi

# concatenate the .scp files together.
for n in `seq 1`; do
    cat $plp_dir/raw_plp_$name.$n.scp || exit 1;
done > $data_dir/feats.scp

num_feats=`cat $data_dir/feats.scp | wc -l`
num_utts=`cat $data_dir/utt2spk | wc -l`

if [ $num_feats -ne $num_utts ]; then
    echo "It seems not all of the feature files were generated ($num_featsf != $num_utts);"
fi
if [ $num_feats -lt $[$num_utts - ($num_utts/20)] ]; then
    echo "Less than 95% the features were successfully generated.  Probably a serious error."
    exit 1;
fi

echo "Succeeded creating PLP features for $name"

#+ bash -x ./extract_feats.sh data_chv/train plp_chv 4
#++ utils/fix_data_dir.sh $data_dir
###############################################################################

utils/fix_data_dir.sh $data_dir

#+ bash -x ./extract_feats.sh data_chv/train plp_chv 4
#++ steps/compute_cmvn_stats.sh data_chv/train plp_chv/make_plp_log plp_chv
###############################################################################

feat_dir=$local_dir/feats

mkdir -p $feat_dir

steps/compute_cmvn_stats.sh \
    $data_dir \
    $feat_dir/make_plp_log \
    $feat_dir \
    || printf "\n####\n#### ERROR: compute_cmvn_stats.sh\n####\n\n" \
    || exit 1;

utils/fix_data_dir.sh $data_dir


echo "$0: splitting feats into 1 subdirs"
utils/split_data.sh $data_dir 1 || exit 1;


#+ bash -x ./compile_Lfst.sh $input_dir $data_dir
###############################################################################

for i in lexicon.txt lexicon_nosil.txt phones.txt; do
    LC_ALL=C sort -i $input_dir/$i -o $input_dir/$i;
done;

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


#+ bash -x ./train_gmm.sh data_chv 40 1000 40 2000 1000 exp_chv
###############################################################################

#tot_gauss_mono=1000
tot_gauss_mono=100
#num_leaves_tri=1000
num_leaves_tri=100
#tot_gauss_tri=2000
tot_gauss_tri=200
num_iters_mono=40
num_iters_tri=40

exp_dir=$local_dir/exp
lang_dir=$local_dir/train/lang

beam=20 # will change to 10 below after 1st pass
nj=1
scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
num_iters=40    # Number of iterations of training
max_iter_inc=30 # Last iter to increase #Gauss on.
#totgauss=1000 # Target #Gaussians.
totgauss=100 # Target #Gaussians.
careful=false
boost_silence=1.0 # Factor by which to boost silence likelihoods in alignment
realign_iters="1 2 3 4 5 6 7 8 9 10 12 14 16 18 20 23 26 29 32 35 38";
config= # name of config file.
power=0.25 # exponent to determine number of gaussians from occurrence counts
cmvn_opts="--norm-vars=true $cmvn_opts"


printf "#### Train Monophones ####\n";

mkdir -p $exp_dir
echo $cmvn_opts > $exp_dir/cmvn_opts # keep track of options to CMVN.

# the dirs we already split data into
sdata=$data_dir/split1;

feats="ark,s,cs:apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk"
feats="$feats scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |"
feats="$feats add-deltas ark:- ark:- |"

# get the feature dimensions of the data just from a small section (JOB 1)
feats_example="`echo $feats | sed s/JOB/1/g`";
feat_dim=`feat-to-dim "$feats_example" -` || exit 1

echo "$0: Initialising monophone system"

utils/run.pl JOB=1 $exp_dir/log/init.log \
        gmm-init-mono \
            --shared-phones=$lang_dir/phones/sets.int \
            "--train-feats=$feats subset-feats --n=10 ark:- ark:-|" \
            $lang_dir/topo \
            $feat_dim \
            $exp_dir/0.mdl \
            $exp_dir/tree \
            || exit 1;

num_gauss=`gmm-info --print-args=false $exp_dir/0.mdl | grep gaussians | awk '{print $NF}'`

echo "!! num_gauss: "$num_gauss

# per-iter increment for #Gauss
inc_gauss=$[($totgauss-$num_gauss)/$max_iter_inc]

echo "$0: Compiling monophone training graphs"

oov_sym=`cat $lang_dir/oov.int` || exit 1;

utils/run.pl JOB=1:1 $exp_dir/log/compile_graphs.JOB.log \
        compile-train-graphs \
            $exp_dir/tree \
            $exp_dir/0.mdl  \
            $lang_dir/L.fst \
            "ark:sym2int.pl --map-oov $oov_sym -f 2- $lang_dir/words.txt < $sdata/JOB/text|" \
            "ark:|gzip -c >$exp_dir/fsts.JOB.gz" \
            || exit 1;

echo ""
echo "### BEGIN FLATSTART MONOPHONE TRAINING ###"

printf "$0: Aligning data from flat start (pass 0)\n"

utils/run.pl JOB=1:1 $exp_dir/log/align.0.JOB.log \
        align-equal-compiled \
            "ark:gunzip -c $exp_dir/fsts.JOB.gz|" \
            "$feats" \
            ark,t:-  \| \
        gmm-acc-stats-ali \
            --binary=true \
            $exp_dir/0.mdl \
            "$feats" \
            ark:- \
            $exp_dir/0.JOB.acc \
            || exit 1;

printf "$0: Estimating model from flat start alignments\n"

gmm-est \
        --min-gaussian-occupancy=3  \
        --mix-up=$num_gauss \
        --power=$power \
        $exp_dir/0.mdl \
        "gmm-sum-accs - $exp_dir/0.*.acc|" \
        $exp_dir/1.mdl \
        2> $exp_dir/log/update.0.log \
        || exit 1;

echo "### BEGIN MAIN EM MONOPHONE TRAINING ###"

    x=1
    while [[ $x -lt $num_iters ]]; do
        
        printf "\n$0: Pass $x\n"
        
        # if this is an iteration where we realign (E-step) data
        if echo $realign_iters | grep -w $x >/dev/null; then
                
                printf "$0: Expectation Step in EM Algorithm\n"
                
                mdl="gmm-boost-silence --boost=$boost_silence"
                mdl="$mdl `cat $lang_dir/phones/optional_silence.csl`"
                mdl="$mdl $exp_dir/$x.mdl - |"
                
                utils/run.pl JOB=1:1 $exp_dir/log/align.$x.JOB.log \
                    gmm-align-compiled \
                        $scale_opts \
                        --beam=$beam \
                        --retry-beam=$[$beam*4] \
                        --careful=$careful \
                        "$mdl" \
                        "ark:gunzip -c $exp_dir/fsts.JOB.gz|" \
                        "$feats" \
                        "ark,t:|gzip -c >$exp_dir/ali.JOB.gz" \
                        || exit 1;
        fi

        printf "$0: Maximize-Step in EM Algorithm\n"
            
        utils/run.pl JOB=1:$nj $exp_dir/log/acc.$x.JOB.log \
                gmm-acc-stats-ali  \
                    $exp_dir/$x.mdl \
                    "$feats" "ark:gunzip -c $exp_dir/ali.JOB.gz|" \
                    $exp_dir/$x.JOB.acc \
                    || exit 1;
        
        utils/run.pl $exp_dir/log/update.$x.log \
                gmm-est \
                    --write-occs=$exp_dir/$[$x+1].occs \
                    --mix-up=$num_gauss \
                    --power=$power \
                    $exp_dir/$x.mdl \
                    "gmm-sum-accs - $exp_dir/$x.*.acc|" \
                    $exp_dir/$[$x+1].mdl \
                    || exit 1;
            
        if [[ $x -le $max_iter_inc ]]; then
            num_gauss=$[$num_gauss+$inc_gauss];
        fi

        x=$[$x+1]
        
done

cp $exp_dir/$x.mdl $exp_dir/final.mdl
cp $exp_dir/$x.occs $exp_dir/final.occs

../../../src/gmmbin/gmm-info ${exp_dir}/monophones/final.mdl

###############################################################################

echo "### BEGIN ALIGNMENT ###"

align_dir=$local_dir/align

scale_opts="--transition-scale=1.0 --acoustic-scale=0.1 --self-loop-scale=0.1"
beam=20
retry_beam=40
careful=false
boost_silence=1.0 # Factor by which to boost silence during alignment.

for f in \
    $lang_dir/oov.int \
    $exp_dir/tree \
    $exp_dir/final.mdl; do
  [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1;
done


mkdir -p $align_dir/log
echo $nj > $align_dir/num_jobs
sdata=$data_dir/split$nj

# frame-splicing options
splice_opts=`cat $exp_dir/splice_opts`
cp $exp_dir/splice_opts $align_dir
# cmvn option
cmvn_opts=`cat $exp_dir/cmvn_opts`
cp $exp_dir/cmvn_opts $align_dir
# delta options
delta_opts=`cat $exp_dir/delta_opts`
cp $exp_dir/delta_opts $align_dir

# if the features are new, split data
[[ -d $sdata && $data_dir/feats.scp -ot $sdata ]] \
    || split_data.sh $data_dir $nj \
    || exit 1;

cp $exp_dir/{tree,final.mdl} $align_dir \
    || exit 1;

cp $exp_dir/final.occs $align_dir;



feat_type=delta
echo "$0: feature type is $feat_type"

feats="ark,s,cs:apply-cmvn $cmvn_opts "
feats+="--utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp "
feats+="scp:$sdata/JOB/feats.scp ark:- | add-deltas $delta_opts ark:- "
feats+="ark:- |"

printf "$0: Aligning data in $data_dir using model from $exp_dir putting alignments in $align_dir\n" 

mdl="gmm-boost-silence --boost=$boost_silence `cat $lang_dir/phones/optional_silence.csl` $align_dir/final.mdl - |"

oov=`cat $lang_dir/oov.int` || exit 1;

transcriptions="ark:utils/sym2int.pl --map-oov $oov -f 2- $lang_dir/words.txt $sdata/JOB/text|";


# We could just use gmm-align in the next line,  but it's less efficient as 
# it compiles the training graphs one by one.
utils/run.pl JOB=1:1 $align_dir/log/align.JOB.log \
    compile-train-graphs \
        $align_dir/tree \
        $align_dir/final.mdl \
        $lang_dir/L.fst \
        "$transcriptions" \
        ark:- \| \
    gmm-align-compiled \
        $scale_opts \
        --beam=$beam \
        --retry-beam=$retry_beam \
        --careful=$careful \
        "$mdl" \
        ark:- "$feats" \
        "ark,t:|gzip -c >$align_dir/ali.JOB.gz" \
    || exit 1;


echo "Finished."
