# takes as input the output from extract-valid-ACC.sh script

# FILE 1
# valid 'output-0' 993 0.584804
# valid 'output-0' 994 0.58572

# FILE 2
# valid 'output-0' 993 0.584804
# valid 'output-0' 994 0.58572

import matplotlib.pyplot as plt
import numpy as np
import csv
from collections import defaultdict
from operator import itemgetter
import sys



###
### USAGE: compare_exp_plot.sh "FILE_1 FILE_2 "
###

infiles=sys.argv[1].split(' ')
alpha=sys.argv[2]

num_exps=len(infiles)

data = defaultdict(dict)

for infile in infiles:
    # example
    # infile: 100: .53

    
    with open(infile) as csvfile:
        reader = csv.reader(csvfile, delimiter=" ")
        
        for row in reader:
            if row[2] == "final":
                pass
            
            else:
                try:
                    data[infile]['0'].append( ( int(row[2]) , float(row[3])))
                except KeyError:
                    data[infile]['0'] = [ ( int(row[2]) , float(row[3]) ) ]


                



for i in range(num_exps):
    valid = [ [*x] for x in zip(* sorted(data[infiles[i]]['0'], key=itemgetter(0))) ]
    plt.plot(valid[0], valid[1], 'C'+str(2*i), label=infiles[i])

        
        


    
plt.legend()
plt.xlabel('Training Iteration')
title=str('Baseline vs. Multi-Task Model Overfitting')

plt.title(title)
plt.ylabel('Validation Accuracy')
plt.show()
