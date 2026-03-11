local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;
local argocd = import 'lib/argocd.libjsonnet';

local instance = inv.parameters._instance;
local app = argocd.App(instance, params.namespace, secrets=true, base='airlock_microgateway') {
  spec+: {
    syncPolicy+: {
      syncOptions+: [
        'ServerSideApply=true',
      ],
    },
  },
};

local appPath =
  local project = std.get(app, 'spec', { project: 'syn' }).project;
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/%s' % [appPath, instance]]: app,
}
