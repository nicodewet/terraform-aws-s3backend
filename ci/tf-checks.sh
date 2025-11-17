#!/usr/bin/env bash

terraform fmt -check -recursive
rc=$?

if [ $rc -eq 0 ]; then
    echo "Terraform formatting OK"
else
    echo "Terraform formatting FAILED."
    echo "\nFix locally with: $ terraform fmt -recursive"
    exit $rc
fi

echo
echo "Running terraform init (backend disabled — this is a module)..."
# ----------------------------------------------------------------------
# Suppress all output from Terraform init (remove this part if you wish)
# ----------------------------------------------------------------------
# The `>/dev/null 2>&1` part does the following:
#
# 1) `>` redirects standard output (stdout, file descriptor 1) to a file.
#    Here, `/dev/null` is a special "black hole" file — anything written there disappears.
#    So `>/dev/null` means "discard all normal output".
#
# 2) `2>&1` redirects standard error (stderr, file descriptor 2) to wherever stdout is currently going.
#    Since stdout is already going to /dev/null, this ensures that error messages are also discarded.
#
# Combined, `>/dev/null 2>&1` means:
# "Run this command and throw away all output — both normal messages and errors."
#
# Example usage:
terraform init -backend=false >/dev/null 2>&1

INIT_RC=$?

if [ $INIT_RC -ne 0 ]; then
    echo "❌ terraform init failed. Cannot proceed to validate."
    exit $INIT_RC
fi

echo
echo "Running terraform validate..."
terraform validate
VAL_RC=$?

if [ $VAL_RC -eq 0 ]; then
    echo "✔ Terraform validate OK"
else
    echo "❌ Terraform validate FAILED."
fi

# Final exit code bubbles up to CI
exit $VAL_RC