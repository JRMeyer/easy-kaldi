Easy Kaldi
================

The scripts in this repository can be used as a template for training neural networks in Kaldi, with the aim to get you going from your data to a trained model as smoothly as possible.

The code here aims to be easily readable and extensible, and makes few assumptions about the kind of data you have and where it's located on disk.

To get started, `easy-kaldi` should be cloned and moved into the `egs` dir of your local version of the [latest Kaldi branch](https://github.com/kaldi-asr/kaldi).

If you're used to typical Kaldi `egs`, you should know that all the scripts here in `utils` / `local` / `steps` exist in this repo. That is, they do not link back to the `wsj` example. This was done to make custom changes to the scripts, making them more readable.



Creating the `input_task` dir
------------------------------------

In order to run `easy-kaldi`, you need to make a new `input_dir` directory. This is the only place you need to make changes for your own corpus.

This directory contains information about the location of your data, lexicon, language model.

Here is an example of the structure of my `input_dir` directory for the corpus called `my-corpus`. As you can see from the `->` arrows, all of these files are softlinks. Using softlinks helps you keep your code and data separate, which becomes important if you're using cloud computing.

```
input_my-corpus/
├── lexicon_nosil.txt -> /data/my-corpus/lexicon/lexicon_nosil.txt
├── lexicon.txt -> /data/my-corpus/lexicon/lexicon.txt
├── corpus.arpabo -> /data/my-corpus/lm/corpus.arpabo
├── test_audio_path -> /data/my-corpus/audio/test_audio_path
├── train_audio_path -> /data/my-corpus/audio/train_audio_path
├── transcripts.test -> /data/my-corpus/audio/transcripts.test
└── transcripts.train -> /data/my-corpus/audio/transcripts.train

0 directories, 7 files
```

Most of these files are standard Kaldi format, and more detailed descriptions of them can be found on [the official docs](http://kaldi-asr.org/doc/data_prep.html).


- `lexicon_nosil.txt` // Standard Kaldi // phonetic dictionary without silence phonemes
- `lexicon.txt` // Standard Kaldi // phonetic dictionary with silence phonemes
- `task.arpabo` // Standard Kaldi // language model in ARPA back-off format
- `test_audio_path` // Custom file! // one-line text file containing absolute path to dir of audio files (eg. WAV) for testing
- `train_audio_path` // Custom file! // one-line text file containing absolute path to dir of audio files (eg. WAV) for training
- `transcripts.test` // Custom file! // A typical Kaldi transcript file, but with only the test utterances
- `transcripts.train` // Custom file! // A typical Kaldi transcript file, but with only the train utterances




Running the scripts
------------------------------------



The scripts will name files and directories dynamically. You will define the name of your input data (ie. corpus) in the initial `input_` dir, and then the rest of the generated dirs and files will be named accordingly. For instance, if you have `input_my-corpus`, then the GMM alignment stage will create `data_my-corpus`, `plp_my-corpus` and `exp_my-corpus`.




### Force Align Training Data (GMM)

`$ ./run_gmm.sh my-corpus test001`

- `my-corpus` should correspond exactly to `input_my-corpus`.

- `test001` is any character string, and is written to the name of the WER file: `WER_nnet3_my-corpus_test001.txt`


### Format data from GMM --> DNN

`$ ./utils/setup_multitask.sh to_dir from_dir "my-corpus"`

- all `nnet3` log files and experimental data will be written to `to_dir` (absolute path). This dir must exist already.

- the output dirs from GMM alignment should all exist at `from_dir` (absolute path)

- the corpus name `"my-corpus"` must correspond to input dir name as such: `input_my-corpus`. However, do not include the initial `input_` here.





### Neural Net Acoustic Modeling (DNN)

`$ ./run_nnet3.sh "my-corpus" hidden-dim num-epochs main-dir`


- first argument is a character string of the corpus name (must correspond to `input_my-corpus`)

- `hidden-dim` is the number of nodes in your hidden layer

- `num-epochs` is num epochs for DNN training.

- `main-dir` is the dir you moved your GMM alignments into. Above we used `to_dir`.