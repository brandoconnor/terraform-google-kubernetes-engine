#!/usr/bin/env bash

# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This function checks to make sure that every
# shebang has a '- e' flag, which causes it
# to exit on error
function check_bash() {
  find . -name "*.sh" | while IFS= read -d '' -r file; do
    if [[ "$file" != *"bash -e"* ]]; then
      echo "$file is missing shebang with -e"
      exit 1
    fi
  done
}

# This function makes sure that the required files for
# releasing to OSS are present
function basefiles() {
  echo "Checking for required files"
  test -f LICENSE || echo "Missing LICENSE"
  test -f README.md || echo "Missing README.md"
}

# This function runs the hadolint linter on
# every file named 'Dockerfile'
function docker() {
  echo "Running hadolint on Dockerfiles"
  find . -name "Dockerfile" -exec hadolint {} \;
}

# This function runs 'terraform validate' against all
# files ending in '.tf'
function check_terraform() {
  #shellcheck disable=SC2156
  find . -name "*.tf" -not -path "./test/fixtures/shared/*" -not -path "./test/fixtures/all_examples/*" -not -path "*/.terraform/*" -exec bash -c 'terraform validate --check-variables=false $(dirname "{}")' \;
  # TODO: doublecheck the find command below. Running manually it works, but under make, it only returns and lints ./test/fixtures/*/network.tf
  echo "Running terraform fmt"
  #shellcheck disable=SC2156
  find . -name "*.tf" -not -path "./test/fixtures/shared/*" -not -path "./test/fixtures/all_examples/*" -not -path "*/.terraform/*" -exec bash -c 'terraform fmt -check=true -write=false "{}"' \;
}

# This function runs 'go fmt' and 'go vet' on every file
# that ends in '.go'
function golang() {
  echo "Running go fmt and go vet"
  find . -name "*.go" -exec go fmt {} \;
  find . -name "*.go" -exec go vet {} \;
}

# This function runs the flake8 linter on every file
# ending in '.py'
function check_python() {
  echo "Running flake8"
  find . -name "*.py" -exec flake8 {} \;
}

# This function runs the shellcheck linter on every
# file ending in '.sh'
function check_shell() {
  echo "Running shellcheck"
  find . -name "*.sh" -exec shellcheck -x {} \;
}

# This function makes sure that there is no trailing whitespace
# in any files in the project.
# There are some exclusions
function check_trailing_whitespace() {
  whitespace_check_cmd="grep -r '[[:blank:]]$' --exclude-dir=\".terraform\" --exclude-dir=\".kitchen\" --exclude=\"*.png\" --exclude=\"*.pyc\" --exclude-dir=\".git\" --exclude=\"terraform.tfvars\" ."
  bash -c "${whitespace_check_cmd} -q"
  rc=$?
  if [ $rc = 0 ]; then
    echo "The following lines have trailing whitespace: "
    bash -c "${whitespace_check_cmd}"
    exit 1
  fi
}

function generate() {
  pip install --user -r ./helpers/generate_modules/requirements.txt
  ./helpers/generate_modules/generate_modules.py
}

function generate_docs() {
  echo "Generating markdown docs with terraform-docs"
  TMPFILE=$(mktemp)
  #shellcheck disable=2006,2086
  for j in $(find ./ -name '*.tf' -type f -not -path "*.terraform*" -exec dirname '{}' \; | sort -u | grep -v ./autogen); do
    terraform-docs markdown "$j" >"$TMPFILE"
    python helpers/combine_docfiles.py "$j"/README.md "$TMPFILE"
  done
  rm -f "$TMPFILE"
}

function check_generate() {
  TMPDIR=$(mktemp -d)
  git worktree add --detach "$TMPDIR" >/dev/null
  cd "$TMPDIR" || exit 1

  generate >/dev/null
  generate_docs >/dev/null

  git diff --stat --exit-code >/dev/null
  rc=$?
  cd - >/dev/null || exit 1

  if [[ $rc -ne 0 ]]; then
    echo '"make generate" creates a diff, run "make generate" and commit the results'
  fi
  rm -rf "$TMPDIR"
  git worktree prune >/dev/null

  echo "Code was generated properly"

  exit $rc
}

function check_generate_docs() {
  TMPDIR=$(mktemp -d)
  git worktree add --detach "$TMPDIR" >/dev/null
  cd "$TMPDIR" || exit 1

  generate_docs >/dev/null
  git diff --stat --exit-code >/dev/null
  rc=$?
  cd - >/dev/null || exit 1

  if [[ $rc -ne 0 ]]; then
    echo '"make generate_docs" creates a diff, run "make generate_docs" and commit the results'
  fi
  rm -rf "$TMPDIR"
  git worktree prune >/dev/null

  echo "Docs were generated properly"

  exit $rc
}
