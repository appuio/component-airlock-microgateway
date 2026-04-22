local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;


local debugConfigMap(instanceParams) = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'debug-configmap',
    namespace: params.default.namespace,
  },
  data: {
    debug: |||
      %s
    ||| % [ std.manifestYamlDoc(instanceParams, indent_array_in_object=false, quote_keys=false) ],
  },
};

{
  [if params.debug then 'debug/%s' % instance.key]: debugConfigMap(std.mergePatch(params.default, instance.value))
  for instance in std.objectKeysValues(params.instances)
}
