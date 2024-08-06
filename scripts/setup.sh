#!/bin/bash

set -oe pipefail

# Branch name to checkout
BRANCH_NAME="master"

# Initialize and update submodules
git submodule update --init --recursive

# Directory for sparse checkout
SPARSE_DIR="docker/lightning-terminal"

# Initialize a new Git repository for sparse checkout with 'master' as the initial branch
mkdir -p $SPARSE_DIR
cd $SPARSE_DIR
git init -b $BRANCH_NAME

# Check if the remote 'origin' already exists
if ! git remote | grep -q 'origin'; then
  git remote add origin https://github.com/lightninglabs/lightning-terminal.git
fi

# Enable sparse checkout
git config core.sparseCheckout true

# Specify the root Dockerfile to checkout
echo "/Dockerfile" >> .git/info/sparse-checkout

# Fetch the specific branch
git fetch --depth 1 origin $BRANCH_NAME

# Checkout the Dockerfile from the specific branch
git checkout $BRANCH_NAME

# Go back to the root directory
cd ..

echo "Sparse checkout of root Dockerfile from $BRANCH_NAME branch completed."