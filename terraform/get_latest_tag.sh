#!/bin/bash
# Fetch and sort tags by semantic version, then return the latest
LATEST_TAG=$(git ls-remote --tags --sort="v:refname" "https://github.com/$1/$2.git" \\
  | awk -F/ '{print \$3}' \\
  | grep -v '{}' \\
  | tail -n1)
# Output as JSON (required for Terraform external data source)
echo "{\"result\":\"$LATEST_TAG\"}"
