// main template for airlock-microgateway
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local license_secret = kube.Secret('airlock-microgateway-license') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    'microgateway-license.txt': params.license,
  },
};

local net_pol = kube.NetworkPolicy('allow-from-waf-namespaces') {
  metadata+: {
    namespace: params.namespace,
  },
  spec: {
    ingress: [ {
      from: [ {
        namespaceSelector: params.network_policy.namespace_selector,
      } ],
    } ],
    policyTypes: [ 'Ingress' ],
  },
};

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

local rules_resources_airlock = {
  apiGroups: [ 'microgateway.airlock.com' ],
  resources: [ '*' ],
  verbs: [ 'get', 'list', 'watch' ],
};
local rbac_aggregated_airlock_view = kube.ClusterRole('airlock-microgateway-aggregated-view') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-view': 'true',
      'rbac.authorization.k8s.io/aggregate-to-cluster-reader': 'true',
    },
    name: 'airlock-microgateway-aggregated-view',
  },
  rules: [
    rules_resources_airlock,
  ],
};
local rbac_aggregated_airlock_edit = kube.ClusterRole('airlock-microgateway-aggregated-edit') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-edit': 'true',
    },
    name: 'airlock-microgateway-aggregated-edit',
  },
  rules: [
    rules_resources_airlock {
      verbs: [ '*' ],
    },
  ],
};
local rbac_aggregated_airlock_admin = kube.ClusterRole('airlock-microgateway-aggregated-admin') {
  metadata: {
    labels: {
      'rbac.authorization.k8s.io/aggregate-to-admin': 'true',
    },
    name: 'airlock-microgateway-aggregated-admin',
  },
  rules: [
    rules_resources_airlock {
      verbs: [ '*' ],
    },
  ],
};

// Define outputs below
{
  '01_license_secret': license_secret,
  '01_network_policy': net_pol,
  [if params.gateway_api.enabled then '02_rbac_aggregated_gateway']: [
    rbac_aggregated_gateway_view,
    rbac_aggregated_gateway_edit,
    rbac_aggregated_gateway_admin,
  ],
  [if params.install_method == 'helm' then '02_rbac_aggregated_airlock']: [
    rbac_aggregated_airlock_view,
    rbac_aggregated_airlock_edit,
    rbac_aggregated_airlock_admin,
  ],
}
