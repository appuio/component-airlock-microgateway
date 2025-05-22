// main template for airlock-microgateway
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local license_secret = kube.Secret('airlock-microgateway-license') {
  metadata: {
    namespace: params.namespace,
  },
  data_: {
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

// Define outputs below
{
  '01_license_secret': license_secret,
  '01_network_policy': net_pol,
}
