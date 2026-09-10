# Before the loop below, which skips it: oh-my-zsh's aliases and options have
# to lose to the files in ~/scripts.
if [[ -r ~/scripts/oh-my-zsh ]]; then
  source ~/scripts/oh-my-zsh
fi

# Load other script files. The (N) glob qualifier expands to nothing when
# ~/scripts is missing, instead of leaving the literal pattern to source.
for file in ~/scripts/*(N); do
  if [[ "${file:t}" != oh-my-zsh ]]; then
    source "$file"
  fi
done

alias sz='source ~/.zshrc'

# Machine-specific settings and secrets live in ~/.zshrc.local, sourced last so
# it wins over everything above. It is never tracked by this repo, which keeps
# real credentials out of `git status` and so out of a stray `gaa` (`git add .`).
if [[ -f ~/.zshrc.local ]]; then
  source ~/.zshrc.local
fi
