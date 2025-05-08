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

// Define outputs below
{
  '01_license_secret': license_secret,
}
