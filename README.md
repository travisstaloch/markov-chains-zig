## usage
```console
$ zig build run -- file1 file2 ...
```
### examples
```console
$ zig build run -- $(ls ../zig/test/behavior/*.zig)
```

```console
$ zig build run -- $(find ../zig/test/behavior/ -name "*.zig")
```

## TODO
* [ ] fix gen repititive spaces
* [ ] fix gen recover when current block not found