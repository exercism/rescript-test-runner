#!/usr/bin/env bash

# Synopsis:
# Run the test runner on a solution.

# Arguments:
# $1: exercise slug
# $2: path to solution folder
# $3: path to output directory

# Output:
# Writes the test results to a results.json file in the passed-in output directory.
# The test results are formatted according to the specifications at https://github.com/exercism/docs/blob/main/building/tooling/test-runners/interface.md

# Example:
# ./bin/run.sh two-fer path/to/solution/folder/ path/to/output/directory/

set -euo pipefail

# If any required arguments is missing, print the usage and exit
if [[ -z "$1" || -z "$2" || -z "$3" ]]; then
    echo "usage: ./bin/run.sh exercise-slug path/to/solution/folder/ path/to/output/directory/"
    exit 1
fi

# Translates a kebab-case slug to PascalCase.
to_pascal_case() {
  awk 'BEGIN{FS="-"; OFS=""} {for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2)); print $0}' <<< "$1"
}

# Strips content not meaningful to the student.
normalize_output() {
  sed -E \
    -e "s|${tmp_dir}/||g" \
    -e $'s/\033\[[0-9;]*[mGKHF]//g' \
    -e '/^Cleaned |^Parsed |^Compiled |^Incremental build failed|Failed to Compile\. See Errors Above|Could not parse Source Files/d' \
    -e '/[^[:space:]]/,$!d' \
    <<< "$1"
}

# Like normalize_output(), but also dedents compile errors.
normalize_compile_output() {
  normalize_output "$1" | sed 's/^  //'
}

slug="$1"
solution_dir="$(realpath "${2%/}")"
output_dir="$(realpath "${3%/}")"
results_file="${output_dir}/results.json"
pascal_slug="$(to_pascal_case "${slug}")"
script_dir="$(realpath "${BASH_SOURCE[0]%/*}/..")"
node_modules="${script_dir}/node_modules"

mkdir -p "${output_dir}"
echo "${slug}: testing..."

if ! tmp_dir=$(mktemp -d "/tmp/exercism-verify-${slug}-XXXXXX"); then
  jq -n '{version: 1, status: "error", message: "The test runner failed to create the temporary directory for your test run. Please open a thread on the Exercism forums.", tests: []}' > "${output_dir}/results.json"
  exit 1
fi
tmp_dir="$(realpath "${tmp_dir}")"  # resolve /tmp -> /private/tmp on macOS
trap 'rm -rf "$tmp_dir"' EXIT

for item in src tests package.json rescript.json; do
  path="${solution_dir}/${item}"
  if [[ ! -e "${path}" ]]; then
    message="The test runner encountered an error copying ${path} to its working folder during your run. Please open a thread on the Exercism forums."
    jq -n --arg msg "${message}" '{version: 1, status: "error", message: $msg}' > "${results_file}"
    exit 1
  fi
  cp -r "${path}" "${tmp_dir}/"
done

mkdir -p "${tmp_dir}/node_modules"

# rescript panics if it can't write to the node_modules during build
if ! cp -r "${node_modules}/rescript-test" "${tmp_dir}/node_modules/rescript-test"; then
  jq -n '{version: 1, status: "error", message: "The test runner encountered an error copying the rescript-test framework to its working folder during your run. Please open a thread on the Exercism forums."}' > "${results_file}"
  exit 1
fi

# Symlink everything else to avoid copying.
for entry in "${node_modules}/"*; do
  name="${entry##*/}"
  [[ "${name}" == "rescript-test" ]] && continue
  ln -s "${entry}" "${tmp_dir}/node_modules/${name}"
done
ln -s "${node_modules}/.bin" "${tmp_dir}/node_modules/.bin"

cd "${tmp_dir}" || exit 1

if ! compile_output="$(node_modules/.bin/rescript build 2>&1)";  then
  message="$(normalize_compile_output "${compile_output}")"
  jq -n --arg msg "${message}" '{version: 1, status: "error", message: $msg}' > "${results_file}"
  exit 1
fi

if ! test_output="$(node node_modules/rescript-test/bin/retest.mjs "tests/${pascal_slug}_test.res.js" 2>&1)"; then
  message="$(normalize_output "${test_output}")"
  jq -n --arg msg "${message}" '{version: 1, status: "fail", message: $msg}' > "${results_file}"
  exit 1
fi

jq -n '{version: 1, status: "pass"}' > "${results_file}"
