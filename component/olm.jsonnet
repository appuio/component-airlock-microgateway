local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local operator_group = operatorlib.OperatorGroup('airlock-microgateway') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
    namespace: params.namespace,
  },
};

local operator_subscription = operatorlib.namespacedSubscription(
  params.namespace,
  'airlock-microgateway',
  params.channel,
  'redhat-operators'
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
  spec+: {
    config+: {
      resources: params.olm.resources,
    },
  },
};

{
  [if params.install_method == 'olm' then '10_operator_group']: operator_group,
  [if params.install_method == 'olm' then '10_operator_subscription']: operator_subscription,
}
