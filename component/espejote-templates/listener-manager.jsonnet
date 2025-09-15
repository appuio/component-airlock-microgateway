local esp = import 'espejote.libsonnet';

local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';

local wantsHttpsListener(obj) = std.get(
  std.get(obj.metadata, 'annotations', {}),
  'alpha.appuio.io/create-gateway-https-listener',
  'false'
) == 'true';

local gwRef(gw) = {
  group: 'gateway.networking.k8s.io',
  kind: 'Gateway',
  name: gw.metadata.name,
  namespace: gw.metadata.namespace,
};

local createListenersForRoute(obj) =
  local gateways = esp.context().gateways;
  local targetGws = [ gw for gw in gateways if std.member(obj.spec.parentRefs, gwRef(gw)) ];
  local desired_listener_hostnames = [ h for h in obj.spec.hostnames ];
  local certSecrets = std.parseJson(std.get(
    std.get(obj.metadata, 'annotations', {}),
    'alpha.appuio.io/gateway-certificate-secrets',
    '{}'
  ));
  std.filter(
    function(o) std.length(o.spec.listeners) > 0,
    [
      {
        apiVersion: gw.apiVersion,
        kind: gw.kind,
        metadata: {
          name: gw.metadata.name,
          namespace: gw.metadata.namespace,
        },
        spec: {
          listeners: [
            {
              local secretName = std.get(certSecrets, h),
              name: 'https-%s' % [ std.strReplace(h, '.', '-') ],
              hostname: h,
              port: 443,
              protocol: 'HTTPS',
              tls: {
                mode: 'Terminate',
                certificateRefs: [
                  {
                    group: '',
                    kind: 'Secret',
                    name: secretName,
                    namespace: obj.metadata.namespace,
                  },
                ],
              },
              allowedRoutes: {
                namespaces: {
                  from: 'Selector',
                  selector: {
                    matchLabels: {
                      'kubernetes.io/metadata.name': obj.metadata.namespace,
                    },
                  },
                },
              },
            }
            for h in desired_listener_hostnames
            if !std.any(
                  std.map(
                    function(l) std.get(l, 'hostname', '') == h,
                    gw.spec.listeners
                  )
                ) && std.objectHas(certSecrets, h)
          ],
        },
      }
      for gw in targetGws
    ]
  );

local removeListenersForRoute(obj) =
  [];

if esp.triggerName() == 'httproute' then
  local tdata = esp.triggerData();
  if tdata != null && wantsHttpsListener(tdata.resource) then (
    if !inDelete(tdata.resource) then
      createListenersForRoute(tdata.resource)
    else if tdata != null then
      removeListenersForRoute(tdata.resource)
  )
