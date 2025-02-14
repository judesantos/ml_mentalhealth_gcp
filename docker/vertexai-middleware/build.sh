#! /bin/sh

# Run this script from the docker directory instead of calling docker build directly
# Handles pre and post build tasks

cp -r ../../certs certs

docker build -t mlops-endpoint --platform=linux/amd64 --no-cache .

rm -rf certs
