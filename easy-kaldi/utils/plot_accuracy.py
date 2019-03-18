# Joshua Meyer 2018
#
# $ python3 plot_accuracy.py -i INFILE -n numTasks -t plotTitle -a auxTask
#
#

# takes as input the output from format_acc.sh script

# train 'output-1' 993 0.584804
# train 'output-0' 993 0.465945
# train 'output-1' 994 0.58572
# train 'output-0' 994 0.461604

import matplotlib.pyplot as plt
import numpy as np
import csv
from collections import defaultdict
from operator import itemgetter

import argparse
parser = argparse.ArgumentParser()

parser.add_argument("-n", "--numTasks")
parser.add_argument("-i", "--infile")
parser.add_argument("-t", "--plotTitle")
parser.add_argument("-a", "--auxTask")

args = parser.parse_args()
task = args.auxTask
data = defaultdict(dict)


with open(args.infile) as csvfile:
    reader = csv.reader(csvfile, delimiter=" ")
    
    for row in reader:
        print(row)
        if row[2] == "final":
            pass

        else:
            try:
                data[row[0]][row[1]].append( ( int(row[2]) , float(row[3]) ) )
            except KeyError:
                data[row[0]][row[1]] = [ ( int(row[2]) , float(row[3]) ) ]


                
def pretty(d, indent=0):
   for key, value in d.items():
      print('\t' * indent + str(key))
      if isinstance(value, dict):
         pretty(value, indent+1)
      else:
         print('\t' * (indent+1) + str(value))




for i in range(1, int(args.numTasks)):
    
    output="'output-" + str(i) + "'"
    
    train = [ [*x] for x in zip(* sorted(data["train"][output], key=itemgetter(0))) ]
    valid = [ [*x] for x in zip(* sorted(data["valid"][output], key=itemgetter(0))) ]
    plt.plot(train[0], train[1], 'C'+str(2*i), label='Clusters Train')
    plt.plot(valid[0], valid[1], 'C'+str((2*i)+1), label='Clusters Dev.')


output="'output-0'"
        
train = [ [*x] for x in zip(* sorted(data["train"][output], key=itemgetter(0))) ]
valid = [ [*x] for x in zip(* sorted(data["valid"][output], key=itemgetter(0))) ]
plt.plot(train[0], train[1], 'C0', label='Training Data')
plt.plot(valid[0], valid[1], 'C1', label='Validation Data')
        
        


    
# if (int(args.numTasks) >= 2):
#     train1 = [ [*x] for x in zip(* sorted(data["train"]["'output-1'"], key=itemgetter(1))) ]
#     valid1 = [ [*x] for x in zip(* sorted(data["valid"]["'output-1'"], key=itemgetter(1))) ]
#     plt.plot(train1[0], train1[1], label='train-TASK-B')
#     plt.plot(valid1[0], valid1[1], label='valid-TASK-B')

    
# if (int(args.numTasks) >= 3):
#     train2 = [ [*x] for x in zip(* sorted(data["train"]["'output-2'"], key=itemgetter(1))) ]
#     valid2 = [ [*x] for x in zip(* sorted(data["valid"]["'output-2'"], key=itemgetter(1))) ]
#     plt.plot(train2[0], train2[1], label='train-TASK-C')
#     plt.plot(valid2[0], valid2[1], label='valid-TASK-C')

    
# if (int(args.numTasks) >= 4):
#     train2 = [ [*x] for x in zip(* sorted(data["train"]["'output-3'"], key=itemgetter(1))) ]
#     valid2 = [ [*x] for x in zip(* sorted(data["valid"]["'output-3'"], key=itemgetter(1))) ]
#     plt.plot(train2[0], train2[1], label='train-TASK-D')
#     plt.plot(valid2[0], valid2[1], label='valid-TASK-D')


    
plt.legend(loc='lower right')
plt.xlabel('Training Iteration')
title=str(args.plotTitle)

plt.title(title)
plt.ylabel('Frame Classification Accuracy')

x1,x2,y1,y2 = plt.axis()
plt.axis((x1,x2,0.0,1.0))


plt.show()
