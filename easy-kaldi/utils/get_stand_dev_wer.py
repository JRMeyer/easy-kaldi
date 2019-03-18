#!/usr/bin/python3
# given a the stem of a WER file name that will match multiple experiments
# get the average and standard dev for those experiments

import sys
import glob, os
import numpy

wer_filenames=sys.argv[1]


WERS=[]
os.chdir("./")
for filename in glob.glob(wer_filenames+"*"):
            with open(filename) as f:
                        line=f.readline().split()
                        WER=line[1]
                        WERS.append(float(WER))

mean="{0:.2f}".format(numpy.mean(WERS))
std="{0:.2f}".format(numpy.std(WERS))

print(str(mean)+"+/-"+str(std))
