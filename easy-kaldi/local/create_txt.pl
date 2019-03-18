#!/usr/bin/env perl
# INPUT:
#   ARGV[0] = the transcript file located in model/input/
#             each line in file should be a <utteranceid> <transcription> pair
#   ARGV[1] = a list of WAV filenames
#             these are expected to have a .wav extension already
#
# OUTPUT:
#   <utteranceid> <transcript> pairs which should be piped to a text file in
#                              prepare_data.sh
#
# FUNCTION: 
#   First all filenames (keys) and their transcriptions (values) are saved
#   to a hash table. Then given a list of filenames, look up their corresponding
#   transcriptions and print them out.
#


$transcript_file = $ARGV[0];
$filename_file = $ARGV[1];

open TRANSCRIPTS, $transcript_file; 
open FILENAMES, $filename_file;

# make a hash dictionary of filename:transcription pairs
my %hash;
while (my $line = <TRANSCRIPTS>) {
    chomp $line;
    my @tokens = split / /, $line;
    my $filename = shift @tokens;
    my $transcript = join(' ', @tokens);
    $hash{$filename} = $transcript;
}

# print out <utteranceid> <transcript> pairs --- these pairs get piped out 
# and printed to a text file in the prepare_data.sh script
while (my $filename = <FILENAMES>){
    # remove whitespaces around filename
	chomp($filename);
    # strip off the extension
	$filename =~ s/\.wav//;
	print "$filename $hash{$filename}\n";
}
