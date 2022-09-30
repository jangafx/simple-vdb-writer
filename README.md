# Simple VDB Writer

A single-file VDB writer in [Odin](https://odin-lang.org/). For an explanation of how it works check out
out the [article](https://jangafx.com/2022/09/29/vdb-a-deep-dive/)!

## Building

You only need to [install Odin](https://odin-lang.org/docs/install/) if you
don't have it already and then run the following command:

```console
$ odin build .
```

This should produce an executable with the same name as the directory of the
project.

## Running

Simply run the executable produced by the above command. This will create a
`test.vdb` file which you can view in [Blender](https://blender.org) or other software capable of
viewing VDB files.