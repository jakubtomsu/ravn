# RAVN Scene

Importer for RSCN, a binary 3D scene format. Also includes a blender exporter.
There is a scene->string formatter for debug/testing purposes.

The format is designed to just be memory mapped and ready to go.

Example commandline usage:
```
odin run ravn\scene -- my_scene.rscn -data -stats
```
