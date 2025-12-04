local kube = import 'kube-ssa-compat.libsonnet';
local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local namespace = params.namespace;

local sa = kube.ServiceAccount('gateway-listener-manager') {
  metadata+: {
    namespace: namespace,
  },
};

local cr = kube.ClusterRole('espejote:gateway-listener-manager') {
  rules: [
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'gateways' ],
      verbs: [ 'get', 'list', 'watch', 'update', 'patch' ],
    },
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'httproutes' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'httproutes', 'httproutes/finalizers' ],
      verbs: [ 'update', 'patch' ],
    },
  ],
};

local crb = kube.ClusterRoleBinding('espejote:gateway-listener-manager') {
  roleRef_: cr,
  subjects_: [ sa ],
};

local role = kube.Role('espejote:gateway-listener-manager') {
  metadata+: {
    namespace: namespace,
  },
  rules: [],
};

local rb = kube.RoleBinding('espejote:gateway-listener-manager') {
  metadata+: {
    namespace: namespace,
  },
  roleRef_: role,
  subjects_: [ sa ],
};

local jsonnetlib =
  esp.jsonnetLibrary('gateway-listener-manager', namespace) {
    spec: {
      data: {
        'config.json': std.manifestJson({
          createListenerAnnotation: params.gateway_listener_manager.create_listener_annotation,
          tlsSecretNameAnnotation: params.gateway_listener_manager.tls_secret_name_annotation,
        }),
      },
    },
  };

local managedresource =
  esp.managedResource('gateway-listener-manager', namespace) {
    metadata+: {
      annotations: {
        'syn.tools/description': |||
          This ManagedResource patches a Gateway found in a HTTPRoutes parentRefs with listeners derived from the route.

          Multiple HTTPRoutes can share the management of a single Gateway listener array by setting custom field managers when applying the listener patches.
        |||,
      },
    },
    spec: {
      serviceAccountRef: { name: sa.metadata.name },
      context: [
        {
          name: 'gateways',
          resource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'Gateway',
            namespace: '',  // all namespaces
          },
        },
      ],
      triggers: [
        {
          name: 'httproute',
          watchResource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'HTTPRoute',
            namespace: '',  // watch all namespaces
          },
        },
      ],
      template: importstr 'espejote-templates/gateway-listener-manager.jsonnet',
    },
  };

if std.member(inv.applications, 'espejote') then
  {
    '80_gateway_listener_manager_rbac': [ sa, cr, crb, role, rb ],
    '80_gateway_listener_manager_managedresource': [ jsonnetlib, managedresource ],
  }
else
  error 'Application "espejote" required for the listener manager feature.'
