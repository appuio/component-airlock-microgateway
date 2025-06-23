local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;


// Define outputs below
{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      annotations+: {
        // Allow pods to be scheduled on any node
        'openshift.io/node-selector': '',
      },
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    },
  },
}
