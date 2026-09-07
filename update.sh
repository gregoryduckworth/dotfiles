#! /usr/bin/env bash

PROFILE=zshrc

read -r -p "Do you want to update your scripts and .$PROFILE? [n/Y]" choice
choice=${choice:-y}
if [[ $choice =~ ^[Yy]$ ]]; then
  echo "Creating .$PROFILE file..."
  sudo cp -R scripts ~/
  sudo cp .$PROFILE ~/.$PROFILE
fi

# Replacing this bash script with zsh loads .$PROFILE; sourcing it here would
# fail on zsh-only builtins and be discarded when this script exits anyway.
echo "Loading .$PROFILE..."
exec /bin/zsh
