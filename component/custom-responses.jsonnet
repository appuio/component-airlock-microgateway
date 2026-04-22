local kube = import 'kube-ssa-compat.libsonnet';
local gw = import 'lib/airlock-microgateway-operator.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prometheus = import 'lib/prometheus.libsonnet';

local hierarchicalConfig = import 'lib/hierarchical-config.libsonnet';
local extractInstances = hierarchicalConfig.extractInstances;
local patchObjects = hierarchicalConfig.patchObjects;

local inv = kap.inventory();

local params = inv.parameters.airlock_microgateway;

local instance = inv.parameters._instance;

local createCustomResponse(name, customResponseConfig) =
    assert std.isObject(customResponseConfig) : "You cannot set an error response to null. It is still referenced from the GatewayParameters";
    kube._Object('microgateway.airlock.com/v1alpha1', 'CustomResponse', name) {
      spec: customResponseConfig,
    };

{
  ['custom-responses/%s/%s' % [instance.key, customResponse.key]]: createCustomResponse(customResponse.key, customResponse.value)
  for customResponse in std.objectKeysValues(std.mergePatch(params.default.customResponses, params.instances['test-instance-02']))
  for instance in std.objectKeysValues(params.instances)
}
+ {[instance.key]: {}
  for instance in std.objectKeysValues(params.instances)}
