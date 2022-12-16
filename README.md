## about
a [markov chain](https://en.wikipedia.org/wiki/Markov_chain) implementation in zig. this tool is useful for generating pseudo-random text based on some input files. outputs to stdout.

## usage
```console
$ zig build run -Dblock-len=8 -- --start-block "pub fn" --maxlen 1000 infile1 infile2 ...
```
#### args
* -Dblock-len : how many bytes to consider when predicting the next
   character.  defaults to 8.
* --start-block : initial seed to start generation. this string should be
   present somewhere in input. generated text will start with this string.
   length must be <= -Dblock-len
* --maxlen : how many characters to generate. does not include length of
   --start-block


### usage examples
```console
$ zig build run -- --start-block "test \"" --maxlen 1000 $(ls ../zig/test/behavior/*.zig)
```

```console
$ zig build run -- --start-block "pub fn" --maxlen 1000 $(find ../zig/test/behavior/ -name "*.zig")
```

## TODO
* [x] gen - fix repititive spaces
* [x] gen - recover when current block not found
* [x] add a block-len build param