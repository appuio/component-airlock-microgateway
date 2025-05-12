local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();

local isOpenshift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

{
  isOpenshift: isOpenshift,
}
