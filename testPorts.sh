#!/bin/bash
#set -euo pipefail 
lsof -i -P -n | grep LISTEN
echo ""
read -e -p 'Enter the IP address of the server or RTU to test: ' IP
echo ""
ping $IP -c 4
echo ""
nc -zv $IP 443
echo ""
nc -zv $IP 61617
echo ""
nc -zv $IP 2377
echo ""
nc -zv $IP 7946
echo ""
nc -zvu $IP 7946
echo ""
nc -zvu $IP 4789
echo ""
nc -zvu $IP 500
echo ""
nc -zvu $IP 4500
echo ""
nc -zv $IP 50
echo ""
nc -zv $IP 51