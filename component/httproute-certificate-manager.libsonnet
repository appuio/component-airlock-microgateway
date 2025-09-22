local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local namespace = params.namespace;

local sa = kube.ServiceAccount('httproute-certificate-manager') {
  metadata+: {
    namespace: namespace,
  },
};

local cr = kube.ClusterRole('espejote:httproute-certificate-manager') {
  rules: [
    {
      apiGroups: [ 'cert-manager.io' ],
      resources: [ 'certificates' ],
      verbs: [ '*' ],
    },
    {
      apiGroups: [ 'gateway.networking.k8s.io' ],
      resources: [ 'gateways', 'httproutes' ],
      verbs: [ 'get', 'list', 'watch' ],
    },
  ],
};

local crb = kube.ClusterRoleBinding('espejote:httproute-certificate-manager') {
  roleRef_: cr,
  subjects_: [ sa ],
};

local role = kube.Role('espejote:httproute-certificate-manager') {
  metadata+: {
    namespace: namespace,
  },
  rules: [],
};

local rb = kube.RoleBinding('espejote:httproute-certificate-manager') {
  metadata+: {
    namespace: namespace,
  },
  roleRef_: role,
  subjects_: [ sa ],
};

local jsonnetlib =
  esp.jsonnetLibrary('httproute-certificate-manager', namespace) {
    spec: {
      data: {
        'config.json': std.manifestJson({
          tlsSecretNameAnnotation: params.httproute_certificate_manager.tls_secret_name_annotation,
          clusterIssuerAnnotation: params.httproute_certificate_manager.cluster_issuer_annotation,
          issuerAnnotation: params.httproute_certificate_manager.issuer_annotation,
          gatewayDefaultClusterIssuerAnnotation: params.httproute_certificate_manager.gateway_default_cluster_issuer_annotation,
          createCertificateAnnotation: params.httproute_certificate_manager.create_certificate_annotation,
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
  esp.managedResource('httproute-certificate-manager', namespace) {
    metadata+: {
      annotations: {
        'syn.tools/description': |||
          This ManagedResource creates a cert-manager Certificate from a HTTPRoute.

          It derives the cert-manager ClusterIssuer from a Gateway annotation.
          The Gateway is referenced in the HTTPRoute parentRefs.
        |||,
      },
    },
    spec: {
      serviceAccountRef: { name: sa.metadata.name },
      context: [
        {
          name: 'httproutes',
          resource: {
            apiVersion: 'gateway.networking.k8s.io/v1',
            kind: 'HTTPRoute',
            namespace: '',  // all namespaces
          },
        },
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
          watchContextResource: {
            name: 'httproutes',
          },
        },
      ],
      template: importstr 'espejote-templates/httproute-certificate-manager.jsonnet',
    },
  };

if std.member(inv.applications, 'espejote') then
  {
    '80_httproute_certificate_manager_rbac': [ sa, cr, crb, role, rb ],
    '80_httproute_certificate_manager_managedresource': [ jsonnetlib, managedresource ],
  }
else
  error 'Application "espejote" required for the httproute-certificate-manager feature.'
