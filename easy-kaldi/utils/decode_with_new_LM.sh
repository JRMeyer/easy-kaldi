#!/bin/bash

prepare_lm.sh # all args from saved model

utils/mkgraph.sh # all args from saved model

steps/decode.sh # new data, new graph, old model
