read -p "Do you want to update your scripts and .bashrc? [n/Y]" choice
choice=${choice:-y}
if [[ $choice =~ ^[Yy]$ ]]; then
  echo "Creating .bashrc file..."
  cp -R scripts ~/
  cp .bashrc ~/.bashrc
fi

echo "Sourcing .bashrc..."
. ~/.bashrc
exec bash