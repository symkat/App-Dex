#!/bin/bash

# Don't allow any uninitialzed variables, trace execution, and exit on any error
set -u
set -x
set -e

mkdir -p packed
export PERL5LIB="$PWD/lib"
fatpack trace scripts/dex
fatpack packlists-for $(cat fatpacker.trace) > packlists
fatpack tree $(cat packlists)
rm packed/dex </dev/null || echo "No packed dex present"

# There's warnings here about Class::XSAccessor from Moo, but this is fine.  It'll fall back to pure perl code when that's not installed to the local perl
fatpack file scripts/dex > packed/dex
chmod a+rx-w packed/dex

rm -rf fatpacker.trace packlists fatlib
