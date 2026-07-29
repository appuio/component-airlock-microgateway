// main template for airlock-microgateway
local kube = import 'kube-ssa-compat.libsonnet';
local gw = import 'lib/airlock-microgateway-operator.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';

local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;
local has_cilium = std.member(inv.applications, 'cilium');

local metadataNamespace(name) = {
  metadata: {
    namespace: name,
  },
};

local has(obj, field) = std.objectHas(obj, field) && obj[field] != null;

// main template for airlock-microgateway
local extractInstances(field) = {
  [name]:
    if has(params.default, field)
    then std.mergePatch(params.default[field], metadataNamespace(name))
    else metadataNamespace(name)
  for name in std.objectFields(params.instances)
};

local patchObjects(key, objs) = [
  if has(params.instances[obj.metadata.namespace], key)
  then std.mergePatch(obj, params.instances[obj.metadata.namespace][key])
  else obj
  for obj in objs
];

local httpRoute(name='') = {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: {
    namespace: name,
    name: name,
  },
  spec: {},
};

local pdb(name='') = {
  apiVersion: 'policy/v1',
  kind: 'PodDisruptionBudget',
  metadata: {
    namespace: name,
    name: name,
    labels: {
      'gateway.networking.k8s.io/gateway-name': name,
    },
  },
};

local egressNetpol(name='') = {
  apiVersion: 'networking.k8s.io/v1',
  kind: 'NetworkPolicy',
  metadata: {
    namespace: name,
    name: name,
  },
};

local namespaces = {
  ['%s/Namespace' % instance.key]: kube.Namespace(instance.key) {
    metadata+: {
      labels+: { 'openshift.io/cluster-monitoring': 'true' },
    },
  } + {
    metadata+: {
      labels+: com.makeMergeable(params.default.namespace.labels),
      annotations: com.makeMergeable(params.default.namespace.annotations),
    },
  }
  for instance in std.objectKeysValues(params.instances)
};

local CiliumNetworkPolicy(name) = {
  apiVersion: 'cilium.io/v2',
  kind: 'CiliumNetworkPolicy',
  metadata: {
    name: name,
  },
};

local GatewayCNPEgress(name) =
  CiliumNetworkPolicy(name) {
    metadata: {
      name: 'internal-dns-egress',
      namespace: name,
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'gateway.networking.k8s.io/gateway-name': name,
          'microgateway.airlock.com/managedBy': params.operatorNamespace,
        },
      },
      egress: [
        {
          toEndpoints: [
            {
              matchLabels: {
                'dns.operator.openshift.io/daemonset-dns': 'default',
                'k8s:io.kubernetes.pod.namespace': 'openshift-dns',
              },
            },
          ],
          toPorts: [
            {
              ports: [
                {
                  port: '5353',
                  protocol: 'UDP',
                },
              ],
              rules: {
                dns: [
                  {
                    matchPattern: '*',
                  },
                ],
              },
            },
          ],
        },
      ],
    },
  };

local GatewayCNPIngress(name) =
  CiliumNetworkPolicy(name) {
    metadata: {
      name: 'allow-ingress-world',
      namespace: name,
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'gateway.networking.k8s.io/gateway-name': name,
          'microgateway.airlock.com/managedBy': params.operatorNamespace,
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
  cnp
  for instance in std.objectKeysValues(params.instances)
  if has_cilium
  for cnp in [
    GatewayCNPIngress(instance.key),
    GatewayCNPEgress(instance.key),
  ]
];

local toFiles(objects) = {
  ['%s/%s-%s' % [ object.metadata.namespace, object.kind, object.metadata.name ]]: object
  for object in objects
};

local prometheusRule(name) = {
  apiVersion: 'monitoring.coreos.com/v1',
  kind: 'PrometheusRule',
  metadata: {
    name: 'sessionStorage-rules',
    namespace: name,
  },
  spec: params.sessionMonitoring.prometheusRuleSpec,
};

local sessionStoreRules = {
  ['%s/SessionMonitoring' % instance.key]: prometheusRule(instance.key)
  for instance in std.objectKeysValues(params.instances)
};


// Define outputs below
toFiles(patchObjects('gateway', com.generateResources(extractInstances('gateway'), gw.Gateway))) +
toFiles(patchObjects('gatewayParameters', com.generateResources(extractInstances('gatewayParameters'), gw.GatewayParameters))) +
toFiles(patchObjects('httpRedirect', com.generateResources(extractInstances('httpRedirect'), httpRoute))) +
toFiles(patchObjects('pdb', com.generateResources(extractInstances('pdb'), pdb))) +
toFiles(patchObjects('egressNetpol', com.generateResources(extractInstances('egressNetpol'), egressNetpol))) +
toFiles(patchObjects('sessionHandling', com.generateResources(extractInstances('sessionHandling'), gw.SessionHandling))) +
toFiles(patchObjects('redisProvider', com.generateResources(extractInstances('redisProvider'), gw.RedisProvider))) +
(if params.sessionMonitoring.enabled then sessionStoreRules else {}) +
toFiles(gateway_cnps) +
namespaces
+ (import 'custom-responses.jsonnet')
+ (import 'lib/debug.jsonnet')
