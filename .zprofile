# Login shells: new Terminal and iTerm2 windows, `zsh -l`, and the login shell
# GUI apps such as VS Code start to read your environment. Puts Homebrew on
# $PATH there, as Homebrew's install instructions say, so a login shell that
# never reaches .zshrc - and oh-my-zsh's brew plugin - still finds brew and
# everything it installed. (A plain `zsh -c` reads neither file.)
for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x "$brew_bin" ]]; then
    eval "$("$brew_bin" shellenv)"
    break
  fi
done
unset brew_bin
