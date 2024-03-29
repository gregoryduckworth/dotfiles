#! /usr/bin/env bash

PROFILE=zshrc

read -p "Do you want to update your scripts and .$PROFILE? [n/Y]" choice
choice=${choice:-y}
if [[ $choice =~ ^[Yy]$ ]]; then
  echo "Creating .$PROFILE file..."
  sudo cp -R scripts ~/
  sudo cp .$PROFILE ~/.$PROFILE
fi

echo "Sourcing .$PROFILE..."
source ~/.$PROFILE
exec /bin/zsh