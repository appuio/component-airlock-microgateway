local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local helm_values = params.helm_values;

{
  values: helm_values,
}
