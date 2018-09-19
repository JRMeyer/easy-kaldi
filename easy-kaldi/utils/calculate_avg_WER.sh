#!/bin/bash

# Joshua Meyer 2017

# script assumes abunch of exp WER files with the WER% in the second col of the
# first line in the file

exp_name=$1

num_exps=0;
total_avg=0;
WERs=''

for i in ${exp_name}*; do
    ((num_exps++));
    line=`head -1 $i`;
    cols=($line);
    WER=${cols[1]}
    WERs="${WERs} ${WER}"
    total_avg=`echo "$total_avg + $WER" | bc`;
done;


avg=`echo "scale=2; $total_avg / $num_exps" | bc`;
total_dev=0
for WER in $WERs; do
   dev=`echo "scale=4;(($WER - $avg)^2)" | bc`
   total_dev=`echo "scale=4; ($total_dev + $dev)" | bc`
done

std=`echo "scale=2; $total_dev / $num_exps" | bc`;

echo "AVERAGE WER over ${num_exps} experiments = $avg +/- $std"
