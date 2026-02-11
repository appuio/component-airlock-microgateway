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
local namespace = (
  if params.monitoring.enabled && std.member(inv.applications, 'prometheus') then
    prometheus.RegisterNamespace(kube.Namespace(params.namespace))
  else if params.monitoring.enabled && inv.parameters.facts.distribution == 'openshift4' then
    kube.Namespace(params.namespace) {
      metadata+: {
        labels+: { 'openshift.io/cluster-monitoring': 'true' },
      },
    }
  else
    kube.Namespace(params.namespace)
) + {
  metadata+: {
    labels+: com.makeMergeable(params.namespaceLabels),
  },
};

local params = params.airlock_microgateway;  // This is the merged global defaults and component instance parameters

local make_gateway(name, cfg) = [
  kube.Namespace(cfg.namespace),
  gw.Gateway(name) {
    metadata+: {
      namespace: cfg.namespace,
    },
    spec:
      params.default + com.makeMergeable(cfg.spec),
  },
];

// Define outputs below
{
  [if std.length(params.gateway_parameters) > 0 then '01_gateway_parameters']:
    com.generateResources(gw.namespaced(params.gateway_parameters), gw.GatewayParameters),
  [if std.length(params.gateways) > 0 then '01_gateways']:
    com.generateResources(gw.namespaced(params.gateways), gw.Gateway),
  [if std.length(params.gateways) > 0 && gw.has_cilium then '01_gateway_networkpolicies']:
    gw.gateway_cnps,
}
