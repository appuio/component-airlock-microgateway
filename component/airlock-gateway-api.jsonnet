local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local gateway_crds =
  local manifests_dir = '%s/manifests/gateway-api' % inv.parameters._base_directory;
  std.flatMap(
    function(file)
      std.parseJson(kap.yaml_load_stream('%s/%s' % [ manifests_dir, file ])),
    kap.dir_files_list(manifests_dir)
  );

local rules_resources_gateway_ronly = {
  apiGroups: [ 'gateway.networking.k8s.io' ],
  resources: [
    'gatewayclasses',
  ],
  verbs: [ 'get', 'list', 'watch' ],
};
local rules_resources_gateway_read = {
  apiGroups: [ 'gateway.networking.k8s.io' ],
  resources: [
    'backendtlspolicies',
    'gateways',
    'grpcroutes',
    'httproutes',
    'referencegrants',
    'tcproutes',
    'tlsroutes',
    'udproutes',
  ],
  verbs: [ 'get', 'list', 'watch' ],
};
local rbac_aggregated_gateway_view = kube.ClusterRole('networking-gatewayapi-aggregated-view') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
    },
    name: 'networking-gatewayapi-aggregated-view',
  },
  rules: [
    rules_resources_gateway_ronly,
    rules_resources_gateway_read,
  ],
};
local rbac_aggregated_gateway_edit = kube.ClusterRole('networking-gatewayapi-aggregated-edit') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
    },
    name: 'networking-gatewayapi-aggregated-edit',
  },
  rules: [
    rules_resources_gateway_ronly,
    rules_resources_gateway_read {
      verbs: [ '*' ],
    },
  ],
};
local rbac_aggregated_gateway_admin = kube.ClusterRole('networking-gatewayapi-aggregated-admin') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    },
    name: 'networking-gatewayapi-aggregated-admin',
  },
  rules: [
    rules_resources_gateway_ronly,
    rules_resources_gateway_read {
      verbs: [ '*' ],
    },
  ],
};

local is_openshift_419_or_higher =
  std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution) &&
  std.parseInt(
    std.get(
      std.get(
        inv.parameters,
        'dynamic_facts',
        {}
      ),
      'openshiftVersion',
      { Minor: '0' }
    ).Minor
  ) >= 19;

if params.gateway_api.enabled then
  {
    '00_gateway_api/aggregated_rbac': [
      rbac_aggregated_gateway_view,
      rbac_aggregated_gateway_edit,
      rbac_aggregated_gateway_admin,
    ],
  } + {
    ['00_gateway_api/' + crd.metadata.name]: [ crd ]
    for crd in gateway_crds
    if !is_openshift_419_or_higher
  }
else
  {}
