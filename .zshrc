# oh-my-zsh, before everything else. It defines aliases, options and
# completions of its own, and the files in ~/scripts are meant to win over
# them, so it cannot wait for the loop below to reach it in glob order. Its
# configuration lives in ~/scripts/oh-my-zsh with the rest of the profile all
# the same, which is why the loop then has to skip the one file it has
# already sourced.
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
