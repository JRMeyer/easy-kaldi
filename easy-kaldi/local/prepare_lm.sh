#!/bin/bash

# USAGE:
#
# local/prepare_lm.sh \
#    $data_dir

# INPUT:
#
#    data_dir/
#       lang/
#          words.txt
#
#       local/
#          lm.arpa
#
#          dict/
#            lexicon.txt

# OUTPUT:
#
# josh@yoga:~/git/kaldi-mirror/egs/kgz/kyrgyz-model$ tree data_org/
# data_org/
# └── lang_decode
#     ├── G.fst              MOST IMPORTANT FILE! (other files copied from lang)
#     ├── L_disambig.fst
#     ├── L.fst
#     ├── oov.int
#     ├── oov.txt
#     ├── phones
#     │   ├── align_lexicon.int
#     │   ├── align_lexicon.txt
#     │   ├── context_indep.csl
#     │   ├── context_indep.int
#     │   ├── context_indep.txt
#     │   ├── disambig.csl
#     │   ├── disambig.int
#     │   ├── disambig.txt
#     │   ├── extra_questions.int
#     │   ├── extra_questions.txt
#     │   ├── nonsilence.csl
#     │   ├── nonsilence.int
#     │   ├── nonsilence.txt
#     │   ├── optional_silence.csl
#     │   ├── optional_silence.int
#     │   ├── optional_silence.txt
#     │   ├── roots.int
#     │   ├── roots.txt
#     │   ├── sets.int
#     │   ├── sets.txt
#     │   ├── silence.csl
#     │   ├── silence.int
#     │   └── silence.txt
#     ├── phones.txt
#     ├── topo
#     └── words.txt




. path.sh


test_dir=$1


# Compile G.fst!
    
cat $test_dir/lm.arpa | arpa2fst - | \
    fstprint | utils/eps2disambig.pl | utils/s2eps.pl | \
    fstcompile --isymbols=$test_dir/words.txt \
               --osymbols=$test_dir/words.txt \
               --keep_isymbols=false \
               --keep_osymbols=false | \
    fstrmepsilon | \
    fstarcsort --sort_type=ilabel \
    > $test_dir/G.fst





# Everything below is only for diagnostic.

fstisstochastic $test_dir/G.fst
      
# The output of fstisstochastic should be like:
# 9.14233e-05 -0.259833
# we do expect the first of these 2 numbers to be close to zero (the second
# is nonzero because the backoff weights make the states sum to >1).
# Because of the <s> fiasco for these particular LMs the first number is not
# as close to zero as it could be.


mkdir -p tmpdir.g

awk '{if(NF==1){ printf("0 0 %s %s\n", $1,$1); }} END{print "0 0 #0 #0"; print "0";}' \
    < $test_dir/dict/lexicon.txt  >tmpdir.g/select_empty.fst.txt

# Checking that G has no cycles with empty words on them (e.g. <s>, </s>);
# this might cause determinization failure of CLG.
# #0 is treated as an empty word.

fstcompile \
    --isymbols=$test_dir/words.txt \
    --osymbols=$test_dir/words.txt \
    tmpdir.g/select_empty.fst.txt | \
    fstarcsort --sort_type=olabel | \
    fstcompose - $test_dir/G.fst \
               > tmpdir.g/empty_words.fst

fstinfo tmpdir.g/empty_words.fst | grep cyclic | grep -w 'y' && \
    echo "Language model has cycles with empty words" && exit 1

rm -r tmpdir.g

printf "Succeeded in formatting data\n\n"
