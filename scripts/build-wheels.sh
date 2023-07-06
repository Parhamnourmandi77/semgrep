#!/usr/bin/env bash
# This script build "wheels", which is a format used by the Pypi package manager
# to distribute binaries (for us semgrep-core) with regular Python code.
# See https://packaging.python.org/en/latest/glossary/#term-Wheel
# and https://realpython.com/python-wheels/ for more information.
# This script is called from our GHA build-xxx workflows.
# It assumes the semgrep-core binary has been copied under cli/src/semgrep/bin
# for pip to package semgrep correctly.

set -e
pip3 install setuptools==67.6.1 wheel
pip3 list
ls -hal /Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/site-packages
cat /Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/site-packages/setuptools-67.6.1.dist-info/WHEEL
cat /Library/Frameworks/Python.framework/Versions/3.11/lib/python3.11/site-packages/wheel-0.40.0.dist-info/WHEEL
cd cli && python3 setup.py sdist bdist_wheel
# Zipping for a stable name to upload as an artifact
zip -r dist.zip dist
