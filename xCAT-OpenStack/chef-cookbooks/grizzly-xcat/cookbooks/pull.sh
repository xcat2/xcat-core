#!/bin/sh
#wq
cd cookbooks
for name in `ls`
do
  echo -e "\n------------cd $name-----------"
  cd $name
  git branch
  git pull
  cd ..
done
