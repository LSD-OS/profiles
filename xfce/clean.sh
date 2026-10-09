#!/usr/bin/env bash

cat << 'EOF'
WARNING:
  → out/     (final ISO + files) will be deleted
  → work/    (build temporary files) will be deleted

Continue? [y/N]
EOF

read -r answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Cleaning..."
    sudo rm -rf out work 2>/dev/null
    echo "Finished."
else
    echo "Cancelled."
fi
