#!/bin/bash
# FiveM Installation Script
#
# Server Files: /mnt/server
apt update -y
apt install -y tar xz-utils curl git git-lfs file jq unzip

mkdir -p /mnt/server
cd /mnt/server

RELEASE_PAGE=$(curl -sSL https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/?$RANDOM)

# Check wether to run installation or update version of script
if [ ! -d "./alpine/" ] && [ ! -d "./server-data/" ]; then
  # Install script
  echo "Beginning installation of new FiveM server."

  # Grab download link from FIVEM_VERSION
  if [ "${FIVEM_VERSION}" == "latest" ] || [ -z ${FIVEM_VERSION} ] ; then
    # Grab latest optional artifact if version requested is latest or null
    LATEST_ARTIFACT=$(echo -e "${RELEASE_PAGE}" | grep "LATEST OPTIONAL" -B1 | grep -Eo 'href=".*/*.tar.xz"' | grep -Eo '".*"' | sed 's/\"//g' | sed 's/\.\///1')
    DOWNLOAD_LINK=$(echo https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${LATEST_ARTIFACT})
  else
    # Grab specific artifact if it exists
    VERSION_LINK=$(echo -e "${RELEASE_PAGE}" | grep -Eo 'href=".*/*.tar.xz"' | grep -Eo '".*"' | sed 's/\"//g' | sed 's/\.\///1' | grep ${FIVEM_VERSION})
    if [ "${VERSION_LINK}" == "" ]; then
      echo -e "Defaulting to directly downloading artifact as the version requested was not found on page."
    else
      DOWNLOAD_LINK=$(echo https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${FIVEM_VERSION}/fx.tar.xz)
    fi
  fi

  # Download artifact and get filetype
  echo -e "Running curl -sSL ${DOWNLOAD_LINK} -o ${DOWNLOAD_LINK##*/}..."
  curl -sSL ${DOWNLOAD_LINK} -o ${DOWNLOAD_LINK##*/}
  echo "Extracting FiveM artifact files..."
  FILETYPE=$(file -F ',' ${DOWNLOAD_LINK##*/} | cut -d',' -f2 | cut -d' ' -f2)

  # Unpack artifact depending on filetype
  if [ "$FILETYPE" == "gzip" ]; then
    tar xzvf ${DOWNLOAD_LINK##*/}
  elif [ "$FILETYPE" == "Zip" ]; then
    unzip ${DOWNLOAD_LINK##*/}
  elif [ "$FILETYPE" == "XZ" ]; then
    tar xvf ${DOWNLOAD_LINK##*/}
  else
    echo -e "Downloaded artifact of unknown filetype. Exiting."
    exit 2
  fi

  # Delete original bash launch script
  rm -rf ${DOWNLOAD_LINK##*/} run.sh

  # Clone resources repo from git
  if [[ "${GIT_ENABLED}" == "true" || "${GIT_ENABLED}" == "1" ]]; then
    echo "Preparing to clone resources repo from git.";

    REPO_DIR="/mnt/server/server-data"
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

    git clone --depth=1 --no-tags --recurse-submodules --shallow-submodules --single-branch ${GIT_BRANCH:+--branch "${GIT_BRANCH}"} "${GIT_REPOURL}" . \
      && echo "Finished cloning resources into ${REPO_DIR} from git." || echo "Failed cloning resources into ${REPO_DIR} from git."

    if command -v git-lfs >/dev/null 2>&1; then
      CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "${GIT_BRANCH:-main}")
      git lfs install --local
      git lfs fetch --exclude="" --include="*" origin "${CURRENT_BRANCH}" || true
      git lfs checkout || true
    else
      echo "git-lfs not installed; skipping LFS fetch."
    fi

    cd /mnt/server
  else
    echo "GIT_ENABLED is disabled; skipping resource checkout. Provide server-data manually."
  fi

  mkdir logs/
  echo "Installation complete."

else
  # Update script
  echo "Beginning update of existing FiveM server artifact."

  # Delete old artifact
  if [ -d "./alpine/" ]; then
    echo "Deleting old artifact..."
    rm -r ./alpine/
    while [ -d "./alpine/" ]; do
      sleep 1s
    done
    echo "Deleted old artifact files successfully."
  fi

  # Grab download link from FIVEM_VERSION
  if [ "${FIVEM_VERSION}" == "latest" ] || [ -z ${FIVEM_VERSION} ] ; then
    # Grab latest optional artifact if version requested is latest or null
    LATEST_ARTIFACT=$(echo -e "${RELEASE_PAGE}" | grep "LATEST OPTIONAL" -B1 | grep -Eo 'href=".*/*.tar.xz"' | grep -Eo '".*"' | sed 's/\"//g' | sed 's/\.\///1')
    DOWNLOAD_LINK=$(echo https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${LATEST_ARTIFACT})
  else
    # Grab specific artifact if it exists
    VERSION_LINK=$(echo -e "${RELEASE_PAGE}" | grep -Eo 'href=".*/*.tar.xz"' | grep -Eo '".*"' | sed 's/\"//g' | sed 's/\.\///1' | grep ${FIVEM_VERSION})
    if [ "${VERSION_LINK}" == "" ]; then
      echo -e "Defaulting to directly downloading artifact as the version requested was not found on page."
    else
      DOWNLOAD_LINK=$(echo https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/${FIVEM_VERSION}/fx.tar.xz)
    fi
  fi

  # Download artifact and get filetype
  echo -e "Running curl -sSL ${DOWNLOAD_LINK} -o ${DOWNLOAD_LINK##*/}..."
  curl -sSL ${DOWNLOAD_LINK} -o ${DOWNLOAD_LINK##*/}
  echo "Extracting FiveM artifact files..."
  FILETYPE=$(file -F ',' ${DOWNLOAD_LINK##*/} | cut -d',' -f2 | cut -d' ' -f2)

  # Unpack artifact depending on filetype
  if [ "$FILETYPE" == "gzip" ]; then
    tar xzvf ${DOWNLOAD_LINK##*/}
  elif [ "$FILETYPE" == "Zip" ]; then
    unzip ${DOWNLOAD_LINK##*/}
  elif [ "$FILETYPE" == "XZ" ]; then
    tar xvf ${DOWNLOAD_LINK##*/}
  else
    echo -e "Downloaded artifact of unknown filetype. Exiting."
    exit 2
  fi

  # Delete original bash launch script
  rm -rf ${DOWNLOAD_LINK##*/} run.sh

  echo "Update complete."

fi