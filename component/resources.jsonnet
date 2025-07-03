// main template for airlock-microgateway
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local GatewayParameter = function(name='') {
  apiVersion: 'microgateway.airlock.com/v1alpha1',
  kind: 'GatewayParameter',
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

local namespacedName(name, namespace='') = {
  local namespaced = std.splitLimit(name, '/', 1),
  local ns = if namespace != '' then namespace else params.namespace,
  namespace: if std.length(namespaced) > 1 then namespaced[0] else ns,
  name: if std.length(namespaced) > 1 then namespaced[1] else namespaced[0],
};

local namespaced(obj) = {
  ['%(namespace)s_%(name)s' % namespacedName(name)]: obj[name] {
    metadata: {
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

{
  [if std.length(params.gateway_classes) > 0 then '01_gateway_classes']: com.generateResources(referencedParam(params.gateway_classes), GatewayClass),
  [if std.length(params.gateway_parameters) > 0 then '01_gateway_parameters']: com.generateResources(namespaced(params.gateway_parameters), GatewayParameter),
}
