#!/bin/bash

if [[ $(awk -F= '/^NAME/{print $2}' /etc/os-release) != "\"Ubuntu\"" ]] || [[ $(awk -F= '/^VERSION_ID/{print $2}' /etc/os-release) != "\"20.04\"" ]]; 
then
	{ echo "Script works only on Ubuntu Focal"; exit $ERRCODE; }
else
	{ echo "Starting installation"; }
fi

cd ..
echo $PWD

sudo apt update #&& sudo apt upgrade -y
sudo apt install python-is-python3 python3-pip -y

curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/get-poetry.py | python -
source $HOME/.poetry/env
poetry install

cd switch
pip install azure.mgmt.compute azure.identity azure.mgmt.network azure.mgmt.storage azure.mgmt.resource azure.monitor.query iohttp





