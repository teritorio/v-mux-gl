#!/bin/sh

set -e

export PROMETHEUS_MULTIPROC_DIR=/prometheus
rm -fr ${PROMETHEUS_MULTIPROC_DIR} && mkdir ${PROMETHEUS_MULTIPROC_DIR}

uvicorn --host 0.0.0.0 --workers 4 vt_merge_proxy.server:app
