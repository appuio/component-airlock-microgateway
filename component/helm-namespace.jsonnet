local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local util = import 'util.libsonnet';

local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local additionalOpenshiftMeta =
  if util.isOpenshift then
    {
      labels+: {
        'openshift.io/cluster-monitoring': 'true',
      },
    }
  else
    {};

// Define outputs below
{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: additionalOpenshiftMeta,
  },
}
