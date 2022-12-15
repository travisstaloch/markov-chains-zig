## usage
```console
$ zig build run -- file1 file2 ...
```
### examples
```console
$ zig build run -- $(ls ../zig/test/behavior/*.zig)
```

```console
$ zig build run -- --start-block main $(find ../zig/test/behavior/ -name "*.zig")
```

## TODO
* [x] fix gen repititive spaces
* [x] fix gen recover when current block not found