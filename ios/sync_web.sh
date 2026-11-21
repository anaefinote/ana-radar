#!/bin/bash
# Copies the sketch (../ANA_PoC/*.pde) and its skins (../ANA_PoC/data/*.png) into Web/, the folder the app
# loads. Run it before building whenever the sketch changes (the cloud build runs it every time).
set -e
cd "$(dirname "$0")"
rm -f Web/*.pde Web/*.png
cp ../ANA_PoC/*.pde Web/
cp ../ANA_PoC/data/*.png Web/
echo "Web/: $(ls Web/*.pde | wc -l | tr -d ' ') sketch files, $(ls Web/*.png | wc -l | tr -d ' ') skins"
