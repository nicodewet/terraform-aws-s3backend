#!/usr/bin/env bash

terraform fmt -check -recursive
rc=$?

if [ $rc -eq 0 ]; then
    echo "Terraform formatting OK"
else
    echo "Terraform formatting FAILED"
fi

exit $rc