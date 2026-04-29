#!/usr/bin/env bash

exec_line="google-chrome-stable --profile-directory=Default --app-id=afnnlnmfnajnjgfdhkacdcldkchhfkde"
echo "Testing: '$exec_line'"

if [[ " $exec_line " =~ [[:space:]]--?profile[[:space:]=] ]]; then
  echo "MATCHED (Regex 1)"
else
  echo "NOT MATCHED (Regex 1)"
fi

# Alternative check
if [[ $exec_line == *" -profile "* || $exec_line == *" -profile="* || $exec_line == *" --profile "* || $exec_line == *" --profile="* ]]; then
  echo "MATCHED (Glob)"
else
  echo "NOT MATCHED (Glob)"
fi
