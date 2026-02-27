#!/bin/usr/env bash

sudo tee /etc/apk/repositories << EOF
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF

sudo apk upgrade --available
sudo apk add zsh zoxide git
sudo apk add gleam erlang
