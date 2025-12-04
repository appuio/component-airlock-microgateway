local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('airlock-microgateway', params.namespace) {
  spec+: {
    syncPolicy+: {
      syncOptions+: [
        'ServerSideApply=true',
      ],
    },
  },
};

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/airlock-microgateway' % appPath]: app,
}
