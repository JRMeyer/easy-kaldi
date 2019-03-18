## Joshua Meyer 2018
##
## format logged training data from compute_prob_valid.* and
## compute_prob_train.* so that the scipt utils/plot_accuracy.py
## and matplotlib can work with it.



logdir=$1
save_to=$2

## NNET2 ##

for i in ${logdir}/compute_prob_valid.*; do
    trial=(${i//./ });
    trial=${trial[1]}
    
    grep -oP 'accuracy is [0-9]\.[0-9]+' $i | while read -r match; do
        myarray=($match);
        echo "valid" "'output-0'" "$trial" "${myarray[2]}" >> $save_to;
    done
done


for i in ${logdir}/compute_prob_train.*; do
    trial=(${i//./ });
    trial=${trial[1]}
    
    grep -oP 'accuracy is [0-9]\.[0-9]+' $i | while read -r match; do
        myarray=($match);
        echo "train" "'output-0'" "$trial" "${myarray[2]}" >> $save_to;
    done
done




## NNET3 ##

# for i in ${logdir}/compute_prob_valid.*; do
#     trial=(${i//./ });
#     trial=${trial[1]};

#     grep -oP '(?<=accuracy for).+(?= per frame)' $i | while read -r match; do
#         myarray=($match);
#         echo "valid" "${myarray[0]}" "$trial" "${myarray[2]}" >> $save_to;
#     done
# done


# for i in ${logdir}/compute_prob_train.*; do
#     trial=(${i//./ });
#     trial=${trial[1]};

#     grep -oP '(?<=accuracy for).+(?= per frame)' $i | while read -r match; do
#         myarray=($match);
#         echo "train" "${myarray[0]}" "$trial" "${myarray[2]}" >> $save_to;
#     done
# done



