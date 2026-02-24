// main template for airlock-microgateway
local kube = import 'kube-ssa-compat.libsonnet';
local gw = import 'lib/airlock-microgateway-operator.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

// main template for airlock-microgateway
local patchGateways(gateways) = [
  params.default.gateway + gateway
  for gateway in gateways
];
local extractInstances(field) = {
  [name]:
    if std.objectHas(params.instances[name], field)
    then params.instances[name][field]
    else {}
  for name in std.objectFields(params.instances)

};

local patchGatewayParameters(gatewayParameters) = [
  params.default.gatewayParameters + gatewayParameter
  for gatewayParameter in gatewayParameters
];

local namespace() = [
  kube.Namespace(instance.key) {
    metadata+: {
      labels+: { 'openshift.io/cluster-monitoring': 'true' },
    },
  }
  + {
    metadata+: {
      labels+: com.makeMergeable(params.default.namespace.labels),
    },
  }
  for instance in std.objectKeysValues(params.instances)
];
// Define outputs below
{
  [if std.length(params.instances) > 0 then '01_gateways']:
    patchGateways(com.generateResources(extractInstances('gateway'), gw.Gateway)) +
    patchGatewayParameters(com.generateResources(extractInstances('gatewayParameters'), gw.GatewayParameters)) +
    namespace(),

  defaultSpec: [params.default],
  params: [params],
  instanceParams: [params.instances],
  //mergedGateway: mergedGateways(),
}
