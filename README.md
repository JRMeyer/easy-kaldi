Easy Kaldi
================

The scripts in this repository can be used as a template for training `nnet3` neural networks in Kaldi, with the aim to get you going from your data to a trained model as smoothly as possible.

The code here aims to be easily readable and extensible, and makes few assumptions about the kind of data you have and where it's located on disk.

To get started, `easy-kaldi` should be cloned and moved into the `egs` dir of your local version of the [latest Kaldi branch](https://github.com/kaldi-asr/kaldi).

If you're used to typical Kaldi `egs`, take note that all `easy-kaldi` scripts in `utils` / `local` / `steps` exist in this repo. That is, they do not link back to the `wsj` example. This was done to make custom changes to the scripts, making them more readable.



Creating the `input_task` dir
------------------------------------

In order to run `easy-kaldi`, you need to make a new `input_dir` directory. This is the only place you need to make changes for your own corpus.

This directory contains information about the location of your data, lexicon, language model.

Here is an example of the structure of my `input_dir` directory for the corpus called `corpus`. As you can see from the `->` arrows, all of these files are softlinks. Using softlinks helps you keep your code and data separate, which becomes important if you're using cloud computing.

```
input_corpus/
├── lexicon_nosil.txt -> /data/corpus/lexicon/lexicon_nosil.txt
├── lexicon.txt -> /data/corpus/lexicon/lexicon.txt
├── corpus.arpabo -> /data/corpus/lm/corpus.arpabo
├── test_audio_path -> /data/corpus/audio/test_audio_path
├── train_audio_path -> /data/corpus/audio/train_audio_path
├── transcripts.test -> /data/corpus/audio/transcripts.test
└── transcripts.train -> /data/corpus/audio/transcripts.train

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



The scripts will name files and directories dynamically. You will define the name of your input data (e.g. `corpus`) in the initial `input_` dir, and then the rest of the generated dirs and files will be named accordingly. For instance, if you have `input_corpus`, then the GMM alignment stage will create `data_corpus`, `plp_corpus` and `exp_corpus`.




### Force Align Training Data (GMM)

`$ ./run_gmm.sh corpus 001`

- `corpus` should correspond exactly to `input_corpus`.

- `001` is any character string, and is written to the name of the WER file: `WER_nnet3_corpus_001.txt`




### Neural Net Acoustic Modeling (DNN)

`$ ./run_nnet3.sh "corpus" $hidden-dim $num-epochs`


- first argument is a character string of the corpus name (must correspond to `input_corpus`)

- `hidden-dim` is the number of nodes in your hidden layer

- `num-epochs` is num epochs for DNN training