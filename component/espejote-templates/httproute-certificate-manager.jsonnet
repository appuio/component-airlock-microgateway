local esp = import 'espejote.libsonnet';

local config = import 'httproute-certificate-manager/config.json';

local createCertificateAnnotation = config.createCertificateAnnotation;
local clusterIssuerAnnotation = config.clusterIssuerAnnotation;
local issuerAnnotation = config.issuerAnnotation;
local tlsSecretNameAnnotation = config.tlsSecretNameAnnotation;
local gatewayDefaultClusterIssuerAnnotation = config.gatewayDefaultClusterIssuerAnnotation;

local gateways = esp.context().gateways;

local result = {
  local this = self,
  unwrap: function()
    if this._type == 'ok' then
      this._result
    else
      error this._error
  ,
  unwrapOr: function(or)
    if this._type == 'ok' then
      this._result
    else
      std.trace('unwrapOr: discarded error: %s' % this._error, or)
  ,
  match: function(
    ok=function(res) result {
      _result: res,
      _type: 'ok',
    }, err=function(msg) result {
      _error: msg,
      _type: 'error',
    }
        )
    if this._type == 'ok' then
      ok(this._result)
    else
      err(this._error),
};

local ok(res) = result {
  _result: res,
  _type: 'ok',
};

local err(msg) = result {
  _error: msg,
  _type: 'error',
};

local gwRef(gw) = {
  group: 'gateway.networking.k8s.io',
  kind: 'Gateway',
  name: gw.metadata.name,
  namespace: gw.metadata.namespace,
};

local getAnnotation(obj, annotation) =
  std.get(std.get(obj.metadata, 'annotations', {}), annotation, '')
;

local targetGwDefaultClusterIssuer(obj) =
  local gws = [ gw for gw in gateways if std.member(obj.spec.parentRefs, gwRef(gw)) ];
  if std.length(gws) == 0 then
    err('no matching Gateway found for HTTPRoute %(namespace)s/%(name)s' % obj.metadata)
  else if std.length(gws) > 1 then
    err('multiple matching parent Gateways found for HTTPRoute %(namespace)s/%(name)s: %(gws)s' % {
      namespace: obj.metadata.namespace,
      name: obj.metadata.name,
      gws: std.join(', ', [ '%(namespace)s/%(name)s' % gw.metadata for gw in gws ]),
    })
  else
    local gw = gws[0];
    local issuer = getAnnotation(gw, gatewayDefaultClusterIssuerAnnotation);
    if issuer == '' then
      err('gateway default cluster issuer annotation %(annotation)s not set on Gateway %(namespace)s/%(name)s' % {
        annotation: gatewayDefaultClusterIssuerAnnotation,
        namespace: gw.metadata.namespace,
        name: gw.metadata.name,
      })
    else
      ok(issuer)
;

local issuerForRoute(route) =
  local ref = if getAnnotation(route, clusterIssuerAnnotation) != '' then
    ok({
      group: 'cert-manager.io',
      kind: 'ClusterIssuer',
      name: getAnnotation(route, clusterIssuerAnnotation),
    })
  else if getAnnotation(route, issuerAnnotation) != '' then
    ok({
      group: 'cert-manager.io',
      kind: 'Issuer',
      name: getAnnotation(route, issuerAnnotation),
    })
  else
    targetGwDefaultClusterIssuer(route).match(
      ok=function(name) ok({
        group: 'cert-manager.io',
        kind: 'ClusterIssuer',
        name: name,
      }),
    );
  ref.match(
    ok=function(ref)
      if ref.name == '' then
        err('issuer name is empty for HTTPRoute %(namespace)s/%(name)s' % route.metadata)
      else
        ok(ref)
    ,
  );

local certForHTTRoute(route) =
  local secretName = getAnnotation(route, tlsSecretNameAnnotation);
  if getAnnotation(route, createCertificateAnnotation) != 'true' || secretName == '' then
    ok(null)
  else if std.length(std.get(route.spec, 'hostnames', [])) == 0 then
    err('no hostnames found for HTTPRoute %(namespace)s/%(name)s' % route.metadata)
  else
    issuerForRoute(route).match(
      ok=function(issuer) ok({
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
          issuerRef: issuer,
          secretName: secretName,
          usages: [
            'digital signature',
            'key encipherment',
          ],
        },
      }),
    )
;

// Main logic: if triggered by an HTTPRoute, process just that one, otherwise
// process all HTTPRoutes in the context and return a list of Certificates (or null
// for those that don't want a certificate).
// Errors are only thrown if triggered by an HTTPRoute, otherwise they are logged
// and the respective route is skipped.
// This helps to ensure that one misconfigured route does not break the entire reconciliation but
// still surfaces errors (and their respective events) on the affected routes.
if esp.triggerName() == 'httproute' then
  (
    local td = esp.triggerData();
    if td.resource != null then certForHTTRoute(td.resource).unwrap()
  )
else
  [
    certForHTTRoute(route).unwrapOr(null)
    for route in esp.context().httproutes
  ]
