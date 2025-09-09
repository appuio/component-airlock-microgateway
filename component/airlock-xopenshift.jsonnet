local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local gateway_group = 'gateway.networking.k8s.io';
local xopenshift_group = 'x-openshift.microgateway.airlock.com';

local crds =
  local manifests_dir = '%s/manifests/airlock-xopenshift' % inv.parameters._base_directory;
  std.flatMap(
    function(file)
      std.parseJson(kap.yaml_load_stream('%s/%s' % [ manifests_dir, file ])),
    kap.dir_files_list(manifests_dir)
  );

local make_xopenshift(crd) =
  crd {
    metadata+: {
      name: std.strReplace(super.name, gateway_group, xopenshift_group),
    },
    spec+: {
      group: xopenshift_group,
    },
  };

local enabled_crds = std.prune(params.airlock_xopenshift.crds);
local basename(crdname) = std.splitLimit(crdname, '.', 1)[0];

local xopenshift_crds = [
  make_xopenshift(crd)
  for crd in crds
  if std.member(std.objectFields(enabled_crds), basename(crd.metadata.name))
];

if params.install_method == 'olm' && params.airlock_xopenshift.enabled then
  {
    [crd.metadata.name]: crd
    for crd in xopenshift_crds
  } +
  {
    enabled_crds:: enabled_crds,
    api_group:: xopenshift_group,
  }
else
  {}
