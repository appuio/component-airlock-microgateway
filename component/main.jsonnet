// main template for airlock-microgateway
local kube = import 'kube-ssa-compat.libsonnet';
local gw = import 'lib/airlock-microgateway-operator.libsonnet';
local btlspolicycnp = import 'lib/backendtlspolicy-cnp.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

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

// One file per object, keyed by namespace and kind+name. Objects that several
// instances generate identically (the RBAC Role in a source namespace watched by
// more than one instance, for example) collapse into a single file.
local toFiles(objects) = std.foldl(
  function(acc, object)
    local key = '%s/%s-%s' % [ object.metadata.namespace, object.kind, object.metadata.name ];
    assert !std.objectHas(acc, key) || acc[key] == object : 'Duplicate object with differing content: ' + key;
    if std.objectHas(acc, key) then acc else acc { [key]: object },
  objects,
  {}
);

local resource(field, generator, name) =
  std.mergePatch(
    generator(kube.hyphenate(name)) + com.makeMergeable(
      if has(params.default, field)
      then std.mergePatch(params.default[field], metadataNamespace(name))
      else metadataNamespace(name)
    ),
    if has(params.instances[name], field) then params.instances[name][field] else {}
  );

// The gateway's own CNPs, only on Cilium-managed clusters
local gatewayCNPs(instance) =
  if has_cilium then [
    GatewayCNPIngress(instance.key),
    GatewayCNPEgress(instance.key),
  ] else [];

// Everything belonging to a single gateway instance, as one flat list of objects
local instanceObjects(instance) =
  [
    resource('gateway', gw.Gateway, instance.key),
    resource('gatewayParameters', gw.GatewayParameters, instance.key),
    resource('httpRedirect', httpRoute, instance.key),
    resource('pdb', pdb, instance.key),
    resource('egressNetpol', egressNetpol, instance.key),
    resource('sessionHandling', gw.SessionHandling, instance.key),
    resource('redisProvider', gw.RedisProvider, instance.key),
  ] + gatewayCNPs(instance) + btlspolicycnp.forInstance(instance.key);

// All per-instance resources, generated in an instance-outer loop
local instanceResources = std.flatMap(instanceObjects, std.objectKeysValues(params.instances));

// Define outputs below
toFiles(instanceResources) +
namespaces
+ (import 'monitoring.jsonnet')
+ (import 'custom-responses.jsonnet')
+ (import 'lib/debug.jsonnet')
