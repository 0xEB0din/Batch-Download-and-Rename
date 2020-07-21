#!/bin/bash
files="./fileslist.txt"
names="./filenames.txt"
while read file <&3 && read name <&4; do
    echo "=> " $file "will be renamed to" "${name%%.*}.pdf"
    cp $file output/
    cd output/
    mv $file "${name%%.*}.pdf"
    cd ../
done 3<$files 4<$names
echo "==> end of files"
