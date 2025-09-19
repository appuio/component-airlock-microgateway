local esp = import 'espejote.libsonnet';

local config = import 'httproute-cert-creator/config.json';

local clusterIssuerAnnotation = config.clusterIssuerAnnotation;
local issuerAnnotation = config.issuerAnnotation;
local secretNameAnnotation = config.secretNameAnnotation;
local defaultIssuerRef = config.defaultIssuerRef;

local issuerForRoute(route) =
  local annotations = std.get(route.metadata, 'annotations', {});
  local ref = if std.objectHas(annotations, clusterIssuerAnnotation) then
    {
      group: 'cert-manager.io',
      kind: 'ClusterIssuer',
      name: annotations[clusterIssuerAnnotation],
    }
  else if std.objectHas(annotations, issuerAnnotation) then
    {
      group: 'cert-manager.io',
      kind: 'Issuer',
      name: annotations[issuerAnnotation],
    }
  else
    {
      group: 'cert-manager.io',
      kind: defaultIssuerRef.kind,
      name: defaultIssuerRef.name,
    };
  assert ref.name != '' : 'issuer name must not be empty';
  ref
;

local certForHTTRoute(route) =
  local secretName = std.get(
    std.get(route.metadata, 'annotations', {}),
    secretNameAnnotation,
    ''
  );
  if secretName == '' || std.length(std.get(route.spec, 'hostnames', [])) == 0 then
    null
  else
    {
      apiVersion: 'cert-manager.io/v1',
      kind: 'Certificate',
      metadata: {
        name: route.metadata.name + '-cert',
        namespace: route.metadata.namespace,
        ownerReferences: [
          {
            apiVersion: route.apiVersion,
            kind: route.kind,
            controller: true,
            name: route.metadata.name,
            uid: route.metadata.uid,
          },
        ],
      },
      spec: {
        dnsNames: route.spec.hostnames,
        issuerRef: issuerForRoute(route),
        secretName: secretName,
        usages: [
          'digital signature',
          'key encipherment',
        ],
      },
    }
;

if esp.triggerName() == 'httproute' then
  (
    local tdata = esp.triggerData();
    if tdata != null then
      certForHTTRoute(tdata.resource)
  )
else
  std.filter(
    function(c) c != null,
    [
      certForHTTRoute(route)
      for route in esp.context().httproutes
    ]
  )
