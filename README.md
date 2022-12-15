## usage
```console
$ zig build run -- --start-block "pub fn" --maxlen 1000 file1 file2 ...
```
### examples
```console
$ zig build run -- --start-block "pub fn" --maxlen 1000 $(ls ../zig/test/behavior/*.zig)
```

```console
$ zig build run -- --start-block "pub fn" --maxlen 1000 $(find ../zig/test/behavior/ -name "*.zig")
```

## TODO
* [x] gen - fix repititive spaces
* [x] gen - recover when current block not found
* [ ] figure out how to add a block-len cli param. this will require
      generalizing Model somehow, maybe by removing its comptime byte_len param.