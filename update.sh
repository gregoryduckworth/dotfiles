read -p "Do you want to update your scripts and .bash_profile? [n/Y]" choice
choice=${choice:-y}
if [[ $choice =~ ^[Yy]$ ]]; then
  echo "Creating .bash_profile file..."
  cp -R scripts ~/
  cp .bash_profile ~/.bash_profile
fi

echo "Sourcing .bash_profile..."
. ~/.bash_profile
exec bash