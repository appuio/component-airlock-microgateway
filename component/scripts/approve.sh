#!/bin/bash

AIRLOCK_INSTALLPLAN=$(kubectl -n "${AIRLOCK_NAMESPACE}" get ip -ojson | jq -r --arg upgrade_job "${JOB_metadata_creationTimestamp}" '.items | sort_by(.metadata.creationTimestamp) | reverse | [.[] |  select((.spec.approved != true) and (.metadata.creationTimestamp < $upgrade_job))][0] | .metadata.name')
if [ "${AIRLOCK_INSTALLPLAN}" != "null" ]; then
  kubectl patch installplan "${AIRLOCK_INSTALLPLAN}" -n "${AIRLOCK_NAMESPACE}" --type merge --patch '{"spec":{"approved":true}}';
fi
