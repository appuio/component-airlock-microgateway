local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local namespace = params.namespace;

local sa = kube.ServiceAccount('httproute-cert-creator-manager') {
  metadata+: {
    namespace: namespace,
  },
};

local cr = kube.ClusterRole('espejote:httproute-cert-creator') {
  rules: [
    {
      apiGroups: [ 'cert-manager.io' ],
      resources: [ 'certificates' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'httproutes' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local crb = kube.ClusterRoleBinding('espejote:httproute-cert-creator') {
  roleRef_: cr,
  subjects_: [ sa ],
};

local role = kube.Role('espejote:httproute-cert-creator') {
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

local rb = kube.RoleBinding('espejote:httproute-cert-creator') {
  metadata+: {
    namespace: namespace,
  },
  roleRef_: role,
  subjects_: [ sa ],
};

local jsonnetlib =
  esp.jsonnetLibrary('httproute-cert-creator', namespace) {
    spec: {
      data: {
        'config.json': std.manifestJson({
          secretNameAnnotation: params.httproute_cert.secret_name_annotation,
          clusterIssuerAnnotation: params.httproute_cert.cluster_issuer_annotation,
          issuerAnnotation: params.httproute_cert.issuer_annotation,
          defaultIssuerRef: params.httproute_cert.default_issuer_ref,
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
  esp.managedResource('httproute-cert-creator', namespace) {
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
          name: 'httproutes',
          resource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'HTTPRoute',
            namespace: '',  // all namespaces
          },
        },
      ],
      triggers: [
        {
          name: 'httproute',
          watchContextResource: {
            name: 'httproutes',
          },
        },
        {
          name: 'jsonnetlib',
          watchResource: jsonnetlib_ref,
        },
      ],
      template: importstr 'espejote-templates/httproute-cert-creator.jsonnet',
    },
  };

if std.member(inv.applications, 'espejote') then
  {
    '80_httproute_cert_creator_rbac': [ sa, cr, crb, role, rb ],
    '80_httproute_cert_creator_managedresource': [ jsonnetlib, managedresource ],
  }
else
  error 'Application "espejote" required for the httproute-cert-creator feature.'
