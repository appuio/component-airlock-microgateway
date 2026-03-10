// main template for airlock-microgateway
local kube = import 'kube-ssa-compat.libsonnet';
local gw = import 'lib/airlock-microgateway-operator.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;
local metadataNamespace(name) = {
  metadata: {
    namespace: name,
  },
};

// main template for airlock-microgateway
local extractInstances(field) = {
  [name]:
    if std.objectHas(params.instances[name], field)
    then std.mergePatch(params.instances[name][field], metadataNamespace(name))
    else metadataNamespace(name)
  for name in std.objectFields(params.instances)
};

local patchObjects(key, objs) = [
  std.mergePatch(params.default[key], obj)
  for obj in objs
];

local httpRoute = function(name='') {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: {
    namespace: name,
  },
  spec: {},
};

local pdb = function(name='') {
  apiVersion: 'policy/v1',
  kind: 'PodDisruptionBudget',
  metadata: {
    namespace: name,
    'gateway.networking.k8s.io/gateway-name': name,
  },
};

local egressNetpol = function(name='') {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: {
    namespace: name,
  },
};

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
  '01_gateways':
    patchObjects('gateway', com.generateResources(extractInstances('gateway'), gw.Gateway)) +
    patchObjects('gatewayParameters', com.generateResources(extractInstances('gatewayParameters'), gw.GatewayParameters)) +
    patchObjects('httpRedirect', com.generateResources(extractInstances('httpRedirect'), httpRoute)) +
    patchObjects('pdb', com.generateResources(extractInstances('pdb'), pdb)) +
    patchObjects('egressNetpol', com.generateResources(extractInstances('egressNetpol'), egressNetpol)) +
    patchObjects('sessionHandling', com.generateResources(extractInstances('sessionHandling'), gw.SessionHandling)) +
    patchObjects('redisProvider', com.generateResources(extractInstances('redisProvider'), gw.RedisProvider)) +
    namespace(),
}
