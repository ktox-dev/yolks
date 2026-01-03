#!/bin/bash
export GIT_TERMINAL_PROMPT=0
cd /home/container

# Auto update resources from git, keeping only the current branch plus submodules and LFS objects.
if [[ "${GIT_ENABLED}" == "true" || "${GIT_ENABLED}" == "1" ]]; then
  echo "Preparing to sync git repository into /home/container/server-data.";

  SSH_DIR="/home/container/.ssh"
  SSH_KEY="${SSH_DIR}/id_ed25519"
  mkdir -p "${SSH_DIR}"
  chmod 700 "${SSH_DIR}"

  if [[ -f "${SSH_KEY}" ]]; then
    chmod 600 "${SSH_KEY}" 2>/dev/null || true
    [[ -f "${SSH_KEY}.pub" ]] && chmod 644 "${SSH_KEY}.pub" 2>/dev/null || true
    if command -v ssh-keyscan >/dev/null 2>&1; then
      ssh-keyscan -H github.com 2>/dev/null | sort -u >> "${SSH_DIR}/known_hosts"
    fi
    export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no"
  else
    echo "SSH key ${SSH_KEY} not found; git operations may fail."
  fi

  REPO_DIR="/home/container/server-data"
  mkdir -p "${REPO_DIR}"
  cd "${REPO_DIR}"

  GIT_REPOURL=${GIT_REPOURL%/}
  # Convert GitHub HTTPS/HTTP URLs to SSH for key-based auth
  if [[ "${GIT_REPOURL}" == https://github.com/* ]]; then
    REPO_PATH=${GIT_REPOURL#https://github.com/}
    REPO_PATH=${REPO_PATH%.git}
    GIT_REPOURL="git@github.com:${REPO_PATH}.git"
  elif [[ "${GIT_REPOURL}" == http://github.com/* ]]; then
    REPO_PATH=${GIT_REPOURL#http://github.com/}
    REPO_PATH=${REPO_PATH%.git}
    GIT_REPOURL="git@github.com:${REPO_PATH}.git"
  fi

  GIT_REPOURL=${GIT_REPOURL%/}
  if [[ ${GIT_REPOURL} != *.git ]]; then
    GIT_REPOURL="${GIT_REPOURL}.git"
  fi

  # Per-repo SSH rewrite (avoids global duplicates and forces submodules to SSH)
  REWRITE_URL="git@github.com:"
  ensure_rewrite() {
    git config --local --replace-all url."${REWRITE_URL}".insteadOf "https://github.com/"
    git config --local --replace-all url."${REWRITE_URL}".insteadOf "http://github.com/"
    git config --local --replace-all url."${REWRITE_URL}".insteadOf "ssh://git@github.com/"
    git config --local --replace-all url."${REWRITE_URL}".insteadOf "git@github.com:"
  }

  rewrite_submodules_to_ssh() {
    # Rewrite any GitHub submodule URLs in .gitmodules to SSH to avoid HTTPS prompts
    if [[ -f .gitmodules ]]; then
      while read -r key url; do
        case "$url" in
          https://github.com/*|http://github.com/*)
            path=${url#*github.com/}
            path=${path%.git}
            ssh_url="git@github.com:${path}.git"
            git config -f .gitmodules "${key}" "${ssh_url}" || true
          ;;
        esac
      done < <(git config -f .gitmodules --get-regexp 'submodule\..*\.url' 2>/dev/null)
      git submodule sync --recursive || true
    fi
    # Ensure local config follows the updated URLs
    git submodule sync --recursive || true
  }

  # Inject rewrite during initial clone so submodules immediately use SSH
  REWRITE_ARGS=(
    -c url."${REWRITE_URL}".insteadOf=https://github.com/
    -c url."${REWRITE_URL}".insteadOf=http://github.com/
    -c url."${REWRITE_URL}".insteadOf=ssh://git@github.com/
    -c url."${REWRITE_URL}".insteadOf=git@github.com:
  )

  git config --global fetch.prune true
  git config --global maintenance.auto false

  TARGET_BRANCH="${GIT_BRANCH}"
  if [[ -z "${TARGET_BRANCH}" ]]; then
    TARGET_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
  fi
  TARGET_BRANCH=${TARGET_BRANCH:-main}

  if [ -d .git ]; then
    echo "Updating existing repository.";
    git remote set-url origin "${GIT_REPOURL}"
    ensure_rewrite
    rewrite_submodules_to_ssh
    git fetch --depth=1 --no-tags origin "${TARGET_BRANCH}" || echo "Fetch failed; continuing with existing files."
    git checkout -B "${TARGET_BRANCH}" "origin/${TARGET_BRANCH}" || echo "Checkout failed; verify branch name."
    git submodule sync --recursive
    git submodule update --init --recursive --depth=1 --progress
    if command -v git-lfs >/dev/null 2>&1; then
      CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "${TARGET_BRANCH}")
      git lfs install --local
      git lfs fetch --exclude="" --include="*" origin "${CURRENT_BRANCH}" || true
      git lfs checkout || true
    else
      echo "git-lfs not installed; skipping LFS fetch."
    fi
    echo "Repository sync complete."
  else
    echo "Cloning repository into ${REPO_DIR}.";
    git "${REWRITE_ARGS[@]}" clone --depth=1 --no-tags --recurse-submodules --shallow-submodules --single-branch ${GIT_BRANCH:+--branch "${GIT_BRANCH}"} "${GIT_REPOURL}" . \
      && echo "Repository cloned." || echo "Repository clone failed."
    ensure_rewrite
    rewrite_submodules_to_ssh
    if command -v git-lfs >/dev/null 2>&1; then
      CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "${TARGET_BRANCH}")
      git lfs install --local
      git lfs fetch --exclude="" --include="*" origin "${CURRENT_BRANCH}" || true
      git lfs checkout || true
    fi
  fi

  cd /home/container
fi

# Make internal Docker IP address available to processes.
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Replace Startup Variables
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Run the Server
eval ${MODIFIED_STARTUP}