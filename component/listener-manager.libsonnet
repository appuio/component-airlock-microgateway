local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local namespace = params.namespace;

local sa = kube.ServiceAccount('listenermanager-manager') {
  metadata+: {
    namespace: namespace,
  },
};

local cr = kube.ClusterRole('espejote:listenermanager') {
  rules: [
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'gateways' ],
      verbs: [ 'get', 'list', 'watch', 'update', 'patch' ],
    },
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'httpsroutes' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local crb = kube.ClusterRoleBinding('espejote:listenermanager') {
  roleRef_: cr,
  subjects_: [ sa ],
};

local role = kube.Role('espejote:listenermanager') {
  metadata+: {
    namespace: namespace,
  },
  rules: [
    {
      apiGroups: [ 'espejote.io' ],
      resources: [ 'jsonnetlibraries' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local rb = kube.RoleBinding('espejote:listenermanager') {
  metadata+: {
    namespace: namespace,
  },
  roleRef_: role,
  subjects_: [ sa ],
};

local jsonnetlib =
  local ndp_params = params.listenermanager;
  esp.jsonnetLibrary('listenermanager', namespace) {
    spec: {
      data: {
        'config.json': std.manifestJson({
          apiVersion: 'TODO',
        }),
      },
    },
  };

local jsonnetlib_ref = {
  apiVersion: jsonnetlib.apiVersion,
  kind: jsonnetlib.kind,
  name: jsonnetlib.metadata.name,
  namespace: jsonnetlib.metadata.namespace,
};

local managedresource =
  esp.managedResource('listenermanager', namespace) {
    metadata+: {
      annotations: {
        'syn.tools/description': |||
          TODO
        |||,
      },
    },
    spec: {
      serviceAccountRef: { name: sa.metadata.name },
      applyOptions: { force: true },
      context: [
        {
          name: 'gateways',
          resource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'Gateway',
          },
        },
      ],
      triggers: [
        {
          name: 'gateway',  // TODO check if required
          watchContextResource: {
            name: 'gateways',
          },
        },
        {
          name: 'httproute',
          watchContextResource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'HTTPRoute',
            namespace: '',  // watch all namespaces
          },
        },
        {
          name: 'jsonnetlib',
          watchResource: jsonnetlib_ref,
        },
      ],
      template: importstr 'espejote-templates/listener-manager.jsonnet',
    },
  };

if std.member(inv.applications, 'espejote') then
  {
    '80_listener_manager_rbac': [ sa, cr, crb, role, rb ],
    '80_listener_manager_managedresource': [ jsonnetlib, managedresource ],
  }
else
  error 'Application "espejote" required for the listener manager feature.'
