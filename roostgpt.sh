#!/bin/bash

ostype=$(uname)
OS=${OS:-$ostype}
echo "OS:[$OS]"

base_url="https://github.com/roost-io/roost-support/releases/download/v1.0.0/roostgpt-"
macos() {
    url="${base_url}macos"
    echo "Download MacOS binary from $url"
    curl -o /var/tmp/roostgpt -L $url
    echo "install roostgpt binary"
    chmod +x /var/tmp/roostgpt
    cp /var/tmp/roostgpt /usr/local/bin
}

linux() {
    url="${base_url}linux"
    echo "Download linux binary from $url"
    curl -o /var/tmp/roostgpt -L $url
    echo "install roostgpt binary"
    chmod +x /var/tmp/roostgpt
    cp /var/tmp/roostgpt /usr/local/bin
}

windows() {
    url="${base_url}win.exe"
    echo "Download windows binary from url"
    curl -o C:/Temp/roostgpt.exe -L $url
    echo "install roostgpt binary"
}

sorry() {
    echo "RoostGPT is not available for your $OS"
}

case $OS in 
    Windows_NT)
	windows
	;;
    Darwin)
	macos
	;;
    Linux)
	linux
	;;
    *)
	sorry
	;;
esac
