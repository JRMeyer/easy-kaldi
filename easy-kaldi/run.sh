#!/bin/bash

dim=8
num_epochs=1
corpus_name="ky"



./run_gmm.sh $corpus_name "test-001"

./run_nnet3.sh $corpus_name $dim $num_epochs


exit
