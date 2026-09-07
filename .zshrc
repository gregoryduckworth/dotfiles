# Load other script files. The (N) glob qualifier expands to nothing when
# ~/scripts is missing, instead of leaving the literal pattern to source.
for file in ~/scripts/*(N); do
  source "$file"
done

alias sz='source ~/.zshrc'

# Machine-specific settings and secrets live in ~/.zshrc.local, sourced last so
# it wins over everything above. It is never tracked by this repo, which keeps
# real credentials out of `git status` and so out of a stray `gaa` (`git add .`).
if [[ -f ~/.zshrc.local ]]; then
  source ~/.zshrc.local
fi
