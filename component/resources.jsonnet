// main template for airlock-microgateway
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local has_cilium = std.member(inv.applications, 'cilium');

local GatewayParameters = function(name='') {
  apiVersion: 'microgateway.airlock.com/v1alpha1',
  kind: 'GatewayParameters',
  metadata: {
    name: name,
  },
};

local GatewayClass = function(name='') {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'GatewayClass',
  metadata: {
    name: name,
  },
};

local Gateway = function(name='') {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'Gateway',
  metadata: {
    name: name,
  },
};

local CiliumNetworkPolicy(name) = {
  apiVersion: 'cilium.io/v2',
  kind: 'CiliumNetworkPolicy',
  metadata: {
    name: name,
  },
};

local namespacedName(name, namespace='') = {
  local namespaced = std.splitLimit(name, '/', 1),
  local ns = if namespace != '' then namespace else params.namespace,
  namespace: if std.length(namespaced) > 1 then namespaced[0] else ns,
  name: if std.length(namespaced) > 1 then namespaced[1] else namespaced[0],
};

local namespaced(obj) = {
  ['%(namespace)s_%(name)s' % namespacedName(name)]: obj[name] {
    metadata+: {
      namespace: namespacedName(name).namespace,
      name: namespacedName(name).name,
    },
  }
  for name in std.objectFields(obj)
  if obj[name] != null
};

local referencedParam(ref) = {
  [class]: {
    [if std.objectHas(ref[class], 'parametersRef') then 'spec']: {
      controllerName: 'microgateway.airlock.com/gatewayclass-controller',
      parametersRef: {
        group: 'microgateway.airlock.com',
        kind: 'GatewayParameters',
        name: namespacedName(ref[class].parametersRef).name,
        namespace: namespacedName(ref[class].parametersRef).namespace,
      },
    },
  } + com.makeMergeable({
    [key]: ref[class][key]
    for key in std.objectFields(ref[class])
    if std.member([ 'metadata', 'spec' ], key)
  })
  for class in std.objectFields(ref)
};

local GatewayCNP(name) =
  local nsName = namespacedName(name);
  CiliumNetworkPolicy(name) {
    metadata: {
      name: nsName.name,
      namespace: nsName.namespace,
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'gateway.networking.k8s.io/gateway-name': nsName.name,
          'microgateway.airlock.com/managedBy': params.namespace,
        },
      },
      ingress: [
        {
          fromEntities: [ 'world' ],
        },
      ],
    },
  };

local gateway_cnps = [
  GatewayCNP(k)
  for k in std.objectFields(params.gateways)
  if params.gateways[k] != null
];


{
  [if std.length(params.gateway_classes) > 0 then '01_gateway_classes']:
    com.generateResources(referencedParam(params.gateway_classes), GatewayClass),
  [if std.length(params.gateway_parameters) > 0 then '01_gateway_parameters']:
    com.generateResources(namespaced(params.gateway_parameters), GatewayParameters),
  [if std.length(params.gateways) > 0 then '01_gateways']:
    com.generateResources(namespaced(params.gateways), Gateway),
  [if std.length(params.gateways) > 0 && has_cilium then '01_gateway_networkpolicies']:
    gateway_cnps,
}
+
(
  if params.gateway_listener_manager.enabled then
    (import 'gateway-listener-manager.libsonnet')
  else
    {}
)
+
(
  if params.httproute_certificate_manager.enabled then
    (import 'httproute-certificate-manager.libsonnet')
  else
    {}
)
