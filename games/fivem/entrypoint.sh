#!/bin/bash
cd /home/container

# Auto update resources from git, keeping only the current branch plus submodules and LFS objects.
if [[ "${GIT_ENABLED}" == "true" || "${GIT_ENABLED}" == "1" ]]; then
  echo "Preparing to sync git repository into /home/container/server-data.";

  REPO_DIR="/home/container/server-data"
  mkdir -p "${REPO_DIR}"
  cd "${REPO_DIR}"

  GIT_REPOURL=${GIT_REPOURL%/}
  if [[ ${GIT_REPOURL} != *.git ]]; then
    GIT_REPOURL="${GIT_REPOURL}.git"
  fi

  if [[ -n "${GIT_USERNAME}" || -n "${GIT_TOKEN}" ]]; then
    GIT_REPOURL="https://${GIT_USERNAME}:${GIT_TOKEN}@$(echo -e "${GIT_REPOURL}" | cut -d/ -f3-)"
  fi

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
    git clone --depth=1 --no-tags --recurse-submodules --shallow-submodules --single-branch ${GIT_BRANCH:+--branch "${GIT_BRANCH}"} "${GIT_REPOURL}" . \
      && echo "Repository cloned." || echo "Repository clone failed."
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