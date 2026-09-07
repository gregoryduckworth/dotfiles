# Load other script files. The (N) glob qualifier expands to nothing when
# ~/scripts is missing, instead of leaving the literal pattern to source.
for file in ~/scripts/*(N); do
  source "$file"
done

alias sz='source ~/.zshrc'
