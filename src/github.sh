#!/usr/bin/env bash

GITHUB_API_URI="https://$PR_SIZE_LABELER_API"
GITHUB_API_HEADER="Accept: application/vnd.github.v3+json"

github::calculate_total_modifications() {
  local -r pr_number="${1}"
  local -r files_to_ignore="${2}"
  if [ -z "$files_to_ignore" ]; then
    local -r body=$(curl -sSL -H "Authorization: token $GITHUB_TOKEN" -H "$GITHUB_API_HEADER" "$GITHUB_API_URI/repos/$GITHUB_REPOSITORY/pulls/$pr_number")

    local -r additions=$(echo "$body" | jq '.additions')
    local -r deletions=$(echo "$body" | jq '.deletions')

    echo $((additions + deletions))
  else
    local -r body=$(curl -sSL -H "Authorization: token $GITHUB_TOKEN" -H "$GITHUB_API_HEADER" "$GITHUB_API_URI/repos/$GITHUB_REPOSITORY/pulls/$pr_number/files?per_page=100")

    local changes=0

    for file in $(echo "$body" | jq -r '.[] | @base64'); do
      _jq() {
        echo "$file" | base64 -d | jq -r "$1"
      }
      local ignore_file=0 # False
      for file_to_ignore in $files_to_ignore; do
        if [ "$file_to_ignore" = "$(basename $(_jq '.filename'))" ]; then
          ignore_file=1 # True
        fi
      done
      if [ $ignore_file -eq 0 ]; then
        ((changes += $(_jq '.changes')))
      fi
    done

    echo $((changes))
  fi
}

github::add_label_to_pr() {
  local -r pr_number="${1}"
  local -r label_to_add="${2}"
  local -r xs_label="${3}"
  local -r s_label="${4}"
  local -r m_label="${5}"
  local -r l_label="${6}"
  local -r xl_label="${7}"

  local -r body=$(curl -sSL -H "Authorization: token $GITHUB_TOKEN" -H "$GITHUB_API_HEADER" "$GITHUB_API_URI/repos/$GITHUB_REPOSITORY/pulls/$pr_number")
  local labels=$(echo "$body" | jq .labels | jq -r ".[] | .name" | grep -e "$xs_label" -e "$s_label" -e "$m_label" -e "$l_label" -e "$xl_label" -v)
  labels=$(printf "%s\n%s" "$labels" "$label_to_add")
  local -r comma_separated_labels=$(github::format_labels "$labels")

  log::message "Final labels: $comma_separated_labels"

  curl -sSL \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "$GITHUB_API_HEADER" \
    -X PATCH \
    -H "Content-Type: application/json" \
    -d "{\"labels\":[$comma_separated_labels]}" \
    "$GITHUB_API_URI/repos/$GITHUB_REPOSITORY/issues/$pr_number"
}

github::format_labels() {
  SAVEIFS=$IFS
  IFS=$'\n'
  local -r labels=($@)
  IFS=$SAVEIFS
  quoted_labels=()

  for ((i = 0; i < ${#labels[@]}; i++)); do
    #    echo "Label $i: ${labels[$i]}"
    label="${labels[$i]}"
    quoted_labels+=("$(str::quote "$label")")
  done

  coll::join_by "," "${quoted_labels[@]/#/}"
}

github::comment() {
  local -r comment=$1

  curl -sSL \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "$GITHUB_API_HEADER" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"body\":\"$comment\"}" \
    "$GITHUB_API_URI/repos/$GITHUB_REPOSITORY/issues/$pr_number/comments"
}
