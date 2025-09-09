local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local airlock_xopenshift = import 'airlock-xopenshift.jsonnet';

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
  params.olm.channel,
  'certified-operators'
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
  spec+: {
    config+: {
      env: [
        {
          name: 'GATEWAY_API_POD_MONITOR_CREATE',
          value: '%s' % params.olm.config.create_pod_monitor,
        },
      ] + if params.airlock_xopenshift.enabled then [
        {
          name: 'GATEWAY_API_%s_API_GROUP' % airlock_xopenshift.enabled_crds[crd],
          value: airlock_xopenshift.api_group,
        }
        for crd in std.objectFields(airlock_xopenshift.enabled_crds)
      ] else [
      ],
    },
  },
};

{
  [if params.install_method == 'olm' then '10_operator_group']: operator_group,
  [if params.install_method == 'olm' then '10_operator_subscription']: operator_subscription,
}
