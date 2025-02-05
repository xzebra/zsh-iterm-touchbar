# GIT
GIT_UNCOMMITTED="${GIT_UNCOMMITTED:-+}"
GIT_UNSTAGED="${GIT_UNSTAGED:-!}"
GIT_UNTRACKED="${GIT_UNTRACKED:-?}"
GIT_STASHED="${GIT_STASHED:-$}"
GIT_UNPULLED="${GIT_UNPULLED:-⇣}"
GIT_UNPUSHED="${GIT_UNPUSHED:-⇡}"

# YARN
YARN_ENABLED=true
TOUCHBAR_GIT_ENABLED=true

# https://unix.stackexchange.com/a/22215
find-up () {
  path=$PWD
  while [[ "$path" != "" && ! -e "$path/$1" ]]; do
    path=${path%/*}
  done
  echo "$path"
}

# Output name of current branch.
git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

# Uncommitted changes.
# Check for uncommitted changes in the index.
git_uncomitted() {
  if ! $(git diff --quiet --ignore-submodules --cached); then
    echo -n "${GIT_UNCOMMITTED}"
  fi
}

# Unstaged changes.
# Check for unstaged changes.
git_unstaged() {
  if ! $(git diff-files --quiet --ignore-submodules --); then
    echo -n "${GIT_UNSTAGED}"
  fi
}

# Untracked files.
# Check for untracked files.
git_untracked() {
  if [ -n "$(git ls-files --others --exclude-standard)" ]; then
    echo -n "${GIT_UNTRACKED}"
  fi
}

# Stashed changes.
# Check for stashed changes.
git_stashed() {
  if $(git rev-parse --verify refs/stash &>/dev/null); then
    echo -n "${GIT_STASHED}"
  fi
}

# Unpushed and unpulled commits.
# Get unpushed and unpulled commits from remote and draw arrows.
git_unpushed_unpulled() {
  # check if there is an upstream configured for this branch
  command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

  local count
  count="$(command git rev-list --left-right --count HEAD...@'{u}' 2>/dev/null)"
  # exit if the command failed
  (( !$? )) || return

  # counters are tab-separated, split on tab and store as array
  count=(${(ps:\t:)count})
  local arrows left=${count[1]} right=${count[2]}

  (( ${right:-0} > 0 )) && arrows+="${GIT_UNPULLED}"
  (( ${left:-0} > 0 )) && arrows+="${GIT_UNPUSHED}"

  [ -n $arrows ] && echo -n "${arrows}"
}

pecho() {
  if [ -n "$TMUX" ]; then
    echo -ne "\ePtmux;\e$*\e\\"
  else
    echo -ne $*
  fi
}

# F1-12: https://github.com/vmalloc/zsh-config/blob/master/extras/function_keys.zsh
# F13-F20: just running read and pressing F13 through F20. F21-24 don't print escape sequences
fnKeys=('^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~' '^[[1;2P' '^[[1;2Q' '^[[1;2R' '^[[1;2S' '^[[15;2~' '^[[17;2~' '^[[18;2~' '^[[19;2~')
touchBarState=''
npmScripts=()
gitBranches=()
lastPackageJsonPath=''

function _clearTouchbar() {
  pecho "\033]1337;PopKeyLabels\a"
}

function _unbindTouchbar() {
  for fnKey in "$fnKeys[@]"; do
    bindkey -s "$fnKey" ''
  done
}

function setKey(){
  if [ ${1} -ge 21 ]; then
    return
  fi

  pecho "\033]1337;SetKeyLabel=F${1}=${2}\a"
  if [ "$4" != "-q" ]; then
    bindkey -s $fnKeys[$1] "$3 \n"
  else
    bindkey $fnKeys[$1] $3
  fi
}

function clearKey(){
  pecho "\033]1337;SetKeyLabel=F${1}=F${1}\a"
}

function is_git_repo() {
  if [[ "$TOUCHBAR_GIT_ENABLED" = true ]] &&
    git rev-parse --is-inside-work-tree &>/dev/null &&
    [[ "$(git rev-parse --is-inside-git-dir 2> /dev/null)" == 'false' ]]; then
    return 0
  else
    return 1
  fi
}

# Returns a list of all the files not ignored by git.
function find_git_files() {
  find . -mindepth 1 -maxdepth 1 -type "$1" -not -path './node_modules*' \
         -a -not -path '*.git*'               \
         -a -not -path './coverage*'          \
         -a -not -path './bower_components*'  \
         -a -not -name '*~'                   \
         -exec sh -c '
           for f do
             git check-ignore -q "$f" ||
             echo "$f"
           done
         ' find-sh {} +
}

function _displayDefault() {
  if [[ $touchBarState != "" ]]; then
    _clearTouchbar
  fi
  _unbindTouchbar
  touchBarState=""

  # CURRENT_DIR
  # -----------
  setKey 1 "📂 $(echo $PWD | awk -F/ '{print $(NF-1)"/"$(NF)}')" _displayFolders '-q'


  # GIT
  # ---
  # Check if the current directory is a git repository and not the .git directory
  if is_git_repo; then
    # Ensure the index is up to date.
    git update-index --really-refresh -q &>/dev/null

    # String of indicators
    local indicators=''

    indicators+="$(git_uncomitted)"
    indicators+="$(git_unstaged)"
    indicators+="$(git_untracked)"
    indicators+="$(git_stashed)"
    indicators+="$(git_unpushed_unpulled)"

    [ -n "${indicators}" ] && touchbarIndicators="🔥[${indicators}]" || touchbarIndicators="🙌";

    setKey 2 "🎋 `git_current_branch`" _displayBranches '-q'
    # If you have lazygit installed, status will call lazygit instead of just
    # git status
    if [[ -x $(which lazygit) ]]; then
      setKey 3 $touchbarIndicators "lazygit"
    else
      setKey 3 $touchbarIndicators "git status"
    fi

    setKey 4 "🔽 pull" "git pull origin $(git_current_branch)"
  else
    clearKey 2
    clearKey 3
    clearKey 4
  fi

  # PACKAGE.JSON
  # ------------
  if [[ $(find-up package.json) != "" ]]; then
      if [[ $(find-up yarn.lock) != "" ]] && [[ "$YARN_ENABLED" = true ]]; then
          setKey 5 "🐱 yarn-run" _displayYarnScripts '-q'
      else
          setKey 5 "⚡️ npm-run" _displayNpmScripts '-q'
    fi
  else
      clearKey 5
  fi
}

function _displayNpmScripts() {
  # find available npm run scripts only if new directory
  if [[ $lastPackageJsonPath != $(find-up package.json) ]]; then
    lastPackageJsonPath=$(find-up package.json)
    npmScripts=($(node -e "console.log(Object.keys($(npm run --json)).sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 19).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='npm'

  fnKeysIndex=1
  for npmScript in "$npmScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $npmScript "npm run $npmScript"
  done

  setKey 1 "👈" _displayDefault '-q'
}

function _displayYarnScripts() {
  # find available yarn run scripts only if new directory
  if [[ $lastPackageJsonPath != $(find-up package.json) ]]; then
    lastPackageJsonPath=$(find-up package.json)
    yarnScripts=($(node -e "console.log([$(yarn run --json 2>>/dev/null | tr '\n' ',')].find(line => line && line.type === 'list' && line.data && line.data.type === 'possibleCommands').data.items.sort((a, b) => a.localeCompare(b)).filter((name, idx) => idx < 19).join(' '))"))
  fi

  _clearTouchbar
  _unbindTouchbar

  touchBarState='yarn'

  fnKeysIndex=1
  for yarnScript in "$yarnScripts[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $yarnScript "yarn run $yarnScript"
  done

  setKey 1 "👈" _displayDefault '-q'
}

function _displayBranches() {
  # List of branches for current repo
  gitBranches=($(node -e "console.log('$(echo $(git branch))'.split(/[ ,]+/).toString().split(',').join(' ').toString().replace('* ', ''))"))

  _clearTouchbar
  _unbindTouchbar

  # change to github state
  touchBarState='github'

  fnKeysIndex=1
  # for each branch name, bind it to a key
  for branch in "$gitBranches[@]"; do
    fnKeysIndex=$((fnKeysIndex + 1))
    setKey $fnKeysIndex $branch "git checkout $branch"
  done

  setKey 1 "👈" _displayDefault '-q'
}

# Unused: shows path to current folder and lets you go back
function _displayPath() {
  _clearTouchbar
  _unbindTouchbar
  touchBarState='path'

  IFS="/" read -rA directories <<< "$PWD"
  fnKeysIndex=2
  for dir in "${directories[@]:1}"; do
    setKey $fnKeysIndex "$dir" "cd $(pwd | cut -d'/' -f-$fnKeysIndex)"
    fnKeysIndex=$((fnKeysIndex + 1))
  done

  setKey 1 "👈" _displayDefault '-q'
}

# Shows current folder contents. Allows traversing current path forwards and
# backwards, and also edit files.
function _displayFolders() {
  _clearTouchbar
  _unbindTouchbar
  touchBarState='folders'

  # Find both directories and files
  if is_git_repo; then
    # If it is a git repo, only list things not included in .gitignore
    directories=$(find_git_files "d" | sed 's|^\./||g')
    files=$(find_git_files "f" | sed 's|^\./||g')
  else
    directories=$(find . -mindepth 1 -maxdepth 1 -type d  \( ! -iname ".*" \) | sed 's|^\./||g')
    files=$(find . -mindepth 1 -maxdepth 1 -type f  \( ! -iname ".*" \) | sed 's|^\./||g')
  fi
  # Set .. dir to go back
  setKey 2 "📂 .." "cd .."
  # Iterate current dir directories
  fnKeysIndex=3
  while IFS= read -r dir; do
    if [ -z "$dir" ]; then
      continue
    fi
    setKey $fnKeysIndex "📂 $dir" "cd $dir"
    fnKeysIndex=$((fnKeysIndex + 1))
  done <<< "$directories"

  while IFS= read -r file; do
    if [ -z "$file" ]; then
      continue
    fi
    setKey $fnKeysIndex "📄 $file" "vim $file"
    fnKeysIndex=$((fnKeysIndex + 1))
  done <<< "$files"

  setKey 1 "👈" _displayDefault '-q'
}

zle -N _displayDefault
zle -N _displayNpmScripts
zle -N _displayYarnScripts
zle -N _displayBranches
zle -N _displayFolders

precmd_iterm_touchbar() {
  if [[ $touchBarState == 'npm' ]]; then
    _displayNpmScripts
  elif [[ $touchBarState == 'yarn' ]]; then
    _displayYarnScripts
  elif [[ $touchBarState == 'github' ]]; then
    _displayBranches
  elif [[ $touchBarState == 'folders' ]]; then
    _displayFolders
  else
    _displayDefault
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd precmd_iterm_touchbar
