#!/bin/bash

dim=512
num_epochs=5
main_dir=MTL
corpus_name="your-corpus-here"



./run_gmm.sh $corpus_name "test-001"

./run_nnet3.sh $corpus_name "tri" "1.0" $dim $num_epochs $main_dir


exit
