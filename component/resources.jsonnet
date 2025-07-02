// main template for airlock-microgateway
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();

// The hiera parameters for the component
local params = inv.parameters.airlock_microgateway;

local GatewayClass = function(name='') {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'GatewayClass',
  metadata: {
    name: name,
  },
};

{
  '01_gateway_classes': com.generateResources(params.gateway_classes, GatewayClass),
}
