#!/bin/bash

ONE_WEEK_AGO=$(date -v-${APPROVE_DELAY} -u +%Y-%m-%dT%H:%M:%SZ)
INSTALLPLAN=$(kubectl -n syn-airlock-microgateway get ip -ojson | jq -r --arg date ${ONE_WEEK_AGO} '.items | sort_by(.metadata.creationTimestamp) | reverse | [.[] |  select((.spec.approved != true) and (.metadata.creationTimestamp < $date))][0] | .metadata.name')
if [ ${INSTALLPLAN} != "null" ]; then
  kubectl patch installplan ${INSTALLPLAN} -n ${NAMESPACE} --type merge --patch '{"spec":{"approved":true}}';
fi
