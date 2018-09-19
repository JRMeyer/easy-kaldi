#!/bin/bash
# Copyright 2010-2012 Microsoft Corporation
#           2012-2013 Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0

# This script creates a fully expanded decoding graph (HCLG) that represents
# all the language-model, pronunciation dictionary, context-dependency,
# and HMM structure in our model.  The output is a Finite State Transducer
# that has word-ids on the output, and pdf-ids on the input (these are indexes
# that resolve to Gaussian Mixture Models).  
# See
#  http://kaldi.sourceforge.net/graph_recipe_test.html
# (this is compiled from this repository using Doxygen,
# the source for this part is in src/doc/graph_recipe_test.dox)


N=3
P=1
tscale=1.0
loopscale=0.1

for x in `seq 5`; do 
    [ "$1" == "--mono" ] && N=1 && P=0 && shift;
    [ "$1" == "--quinphone" ] && N=5 && P=2 && shift;
    [ "$1" == "--transition-scale" ] && tscale=$2 && shift 2;
    [ "$1" == "--self-loop-scale" ] && loopscale=$2 && shift 2;
done

if [ $# != 6 ]; then
    echo "Usage: utils/mkgraph.sh [options] <lang-dir> <model-dir> <graphdir>"
    echo "e.g.: utils/mkgraph.sh data/lang_decode exp/tri1/ exp/tri1/graph"
    echo " Options:"
    echo " --mono          #  For monophone models."
    echo " --quinphone     #  For models with 5-phone context (3 is default)"
    exit 1;
fi

if [ -f path.sh ]; then . ./path.sh; fi



input_dir=$1
data_dir=$2
lang_decode_dir=$3
graph_dir=$4
tree=$5
model=$6



# move all info about lexicon (which we needed for training) into
# new dir for decoding
cp -r $data_dir/lang $lang_decode_dir
cp -r $data_dir/local/dict $lang_decode_dir/dict
cp $input_dir/task.arpabo $lang_decode_dir/lm.arpa



for f in $lang_decode_dir/L.fst \
             $lang_decode_dir/lm.arpa \
             $lang_decode_dir/phones.txt \
             $lang_decode_dir/words.txt \
             $lang_decode_dir/phones/silence.csl \
             $lang_decode_dir/phones/disambig.int \
             $model \
             $tree; do
    [ ! -f $f ] && echo "mkgraph.sh: expected $f to exist" && exit 1;
done



mkdir -p $graph_dir
mkdir -p $lang_decode_dir/tmp



#####################
### Compile G.fst ###
#####################

# this following script should not make reference to the original data_dir, if
# I want to have an intuitive script. G.fst has nothing to do with training,
# and if I make a data_decode dir by copying the data_dir, that copying
# should mean that I should be able to only reference the data_decode dir

# create G.fst
local/prepare_lm.sh \
    $lang_decode_dir \
    || printf "\n####\n#### ERROR: prepare_lm.sh\n####\n\n" \
    || exit 1;


##########
### LG ###
##########

echo "### compile LG.fst ###"

# If LG.fst does not exist or is older than its sources, make it...

if [[ ! -s $lang_decode_dir/tmp/LG.fst || $lang_decode_dir/tmp/LG.fst -ot $lang_decode_dir/G.fst || \
    $lang_decode_dir/tmp/LG.fst -ot $lang_decode_dir/L_disambig.fst ]]; then

    fsttablecompose \
        $lang_decode_dir/L_disambig.fst \
        $lang_decode_dir/G.fst | \
        fstdeterminizestar --use-log=true | \
        fstminimizeencoded | \
        fstpushspecial | \
        fstarcsort --sort_type=ilabel \
        > $lang_decode_dir/tmp/LG.fst \
        || exit 1;

    fstisstochastic \
        $lang_decode_dir/tmp/LG.fst \
        || echo "[info]: LG not stochastic."
fi





###########
### CLG ###
###########

echo "### compile CLG.fst ###"

clg=$lang_decode_dir/tmp/CLG_${N}_${P}.fst

if [[ ! -s $clg || $clg -ot $lang_decode_dir/tmp/LG.fst ]]; then

    fstcomposecontext --context-size=$N --central-position=$P \
        --read-disambig-syms=$lang_decode_dir/phones/disambig.int \
        --write-disambig-syms=$lang_decode_dir/tmp/disambig_ilabels_${N}_${P}.int \
        $lang_decode_dir/tmp/ilabels_${N}_${P} \
        < $lang_decode_dir/tmp/LG.fst | \
        fstarcsort --sort_type=ilabel \
        > $clg;

    fstisstochastic $clg \
        || echo "[info]: CLG not stochastic."
fi




##########
### Ha ###
##########

echo "### compile Ha.fst ###"

if [[ ! -s $graph_dir/Ha.fst || $graph_dir/Ha.fst -ot $model  \
            || $graph_dir/Ha.fst -ot $lang_decode_dir/tmp/ilabels_${N}_${P} ]]; then

    make-h-transducer \
        --disambig-syms-out=$graph_dir/disambig_tid.int \
        --transition-scale=$tscale \
        $lang_decode_dir/tmp/ilabels_${N}_${P} \
        $tree \
        $model \
        > $graph_dir/Ha.fst \
        || exit 1;
    
fi





#############
### HCLGa ###
#############

echo "### compile HCLGa.fst ###"

if [[ ! -s $graph_dir/HCLGa.fst || \
    $graph_dir/HCLGa.fst -ot $graph_dir/Ha.fst || \
    $graph_dir/HCLGa.fst -ot $clg ]]; then
    
    fsttablecompose \
        $graph_dir/Ha.fst $clg | \
        fstdeterminizestar --use-log=true | \
        fstrmsymbols $graph_dir/disambig_tid.int | \
        fstrmepslocal | \
        fstminimizeencoded \
        > $graph_dir/HCLGa.fst \
        || exit 1;
    
    fstisstochastic $graph_dir/HCLGa.fst \
        || echo "HCLGa is not stochastic"
fi




############
### HCLG ###
############

echo "### compile HCLG.fst ###"

if [[ ! -s $graph_dir/HCLG.fst || \
    $graph_dir/HCLG.fst -ot $graph_dir/HCLGa.fst ]]; then
    
    add-self-loops --self-loop-scale=$loopscale --reorder=true \
        $model \
        < $graph_dir/HCLGa.fst \
        > $graph_dir/HCLG.fst \
        || exit 1;
    
    if [ $tscale == 1.0 -a $loopscale == 1.0 ]; then
        # No point doing this test if transition-scale not 1, as it will fail. 
        fstisstochastic $graph_dir/HCLG.fst \
            || echo "[info]: final HCLG is not stochastic."
    fi
fi



# keep a copy of the lexicon and a list of silence phones with HCLG...
# this means we can decode without reference to the $lang_decode_dir directory.


cp $lang_decode_dir/words.txt $graph_dir/ || exit 1;
mkdir -p $graph_dir/phones
# might be needed for ctm scoring
cp $lang_decode_dir/phones/word_boundary.* $graph_dir/phones/ 2>/dev/null
cp $lang_decode_dir/phones/align_lexicon.* $graph_dir/phones/ 2>/dev/null

cp $lang_decode_dir/phones/disambig.{txt,int} $graph_dir/phones/ 2> /dev/null
cp $lang_decode_dir/phones/silence.csl $graph_dir/phones/ || exit 1;
# ignore the error if it's not there.
cp $lang_decode_dir/phones.txt $graph_dir/ 2> /dev/null 

# to make const fst:
# fstconvert --fst_type=const $graph_dir/HCLG.fst $graph_dir/HCLG_c.fst
am-info --print-args=false \
    $model | \
    grep pdfs | \
    awk '{print $NF}' \
    > $graph_dir/num_pdfs
