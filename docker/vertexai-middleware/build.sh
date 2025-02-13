#! /bin/sh

cp -r ../../certs certs

docker build -t mlops-endpoint --platform=linux/amd64 --no-cache .

rm -rf certs
