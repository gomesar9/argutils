#!/bin/bash

mkdir -p ./files
rm -f ./files/*

touch -d "1 day ago" ./files/01_day
touch -d "$(date -d 'today' '+%Y-%m-%d 00:00:00')" ./files/00_first
touch -d "$(date -d '1 day ago' '+%Y-%m-%d 23:59:59')" ./files/01_last
touch -d "$(date -d '1 days ago' '+%Y-%m-%d 00:00:00')" ./files/01_first

touch -d "$(date -d '2 days ago' '+%Y-%m-%d 23:59:59')" ./files/02_last
touch -d "$(date -d '2 days ago' '+%Y-%m-%d 00:00:00')" ./files/02_first
touch -d "$(date -d '3 days ago' '+%Y-%m-%d 23:59:59')" ./files/03_last

ls -lh ./files
