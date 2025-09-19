local esp = import 'espejote.libsonnet';
local config = import 'listenermanager/config.json';

local matchAnnotation = config.matchAnnotation;
local tlsSecretAnnotation = config.tlsSecretAnnotation;

local finalizer = 'airlock-microgateway.appuio.io/listenermanager';
local parentRefTrackAnnotation = 'internal.listenermanager.airlock-microgateway.appuio.io/track-parent-refs';

// Returns all duplicates in an array based on an id function.
local findDuplicates(a, id=function(o) o) =
  std.foldl(
    function(prev, o)
      prev {
        set: std.set(super.set + [ o ], id),
        duplicates: super.duplicates + if std.member(std.map(id, super.set), id(o)) then [ o ] else [],
      },
    a,
    { set: [], duplicates: [] }
  )
;

local inDelete(obj) = std.get(obj.metadata, 'deletionTimestamp', '') != '';

local wantsHttpsListener(obj) = std.get(
  std.get(obj.metadata, 'annotations', {}), matchAnnotation, 'false'
) == 'true';

local routeHostnameRefs(route) =
  std.mapWithIndex(
    function(index, hostname)
      {
        name: route.metadata.name,
        namespace: route.metadata.namespace,
        hostname: hostname,
        pos: index,
      },
    std.get(route.spec, 'hostnames', []),
  )
;

local gwRef(gw) = {
  group: 'gateway.networking.k8s.io',
  kind: 'Gateway',
  name: gw.metadata.name,
  namespace: gw.metadata.namespace,
};

local gfRefId(gwRef) = '%(group)s/%(kind)s/%(namespace)s/%(name)s' % gwRef;

// applyObjFromObj strips all fields except apiVersion, kind, namespace, and name from the given object
local applyObjFromObj(obj) = {
  apiVersion: obj.apiVersion,
  kind: obj.kind,
  metadata: {
    name: obj.metadata.name,
    namespace: obj.metadata.namespace,
  },
};

local httpRouteFieldManager(obj) =
  'esp:httproute:%(namespace)s:%(name)s' % obj.metadata
;

local traceJSON(msg, obj) =
  std.trace('%s: %s' % [ msg, std.manifestJsonMinified(obj) ], obj)
;

local prevParentRefs(obj) =
  std.parseJson(std.get(
    std.get(obj.metadata, 'annotations', {}),
    parentRefTrackAnnotation,
    '[]'
  ))
;

local ensureListenerAndFinalizer(obj) =
  local gateways = esp.context().gateways;
  local targetGws = traceJSON('targetGws', [ gw for gw in gateways if std.member(obj.spec.parentRefs, gwRef(gw)) ]);
  local desiredListeners = routeHostnameRefs(obj);
  local secretName = std.get(
    std.get(obj.metadata, 'annotations', {}),
    tlsSecretAnnotation,
    ''
  );
  traceJSON('ensureListenerAndFinalizer', [
    // Remove listeners from gateways that are no longer referenced by this HTTPRoute
    esp.applyOptions(
      applyObjFromObj(gw) {
        spec: {
          listeners: [],
        },
      },
      fieldManager=httpRouteFieldManager(obj)
    )
    for gw in std.setDiff(std.set(prevParentRefs(obj), gfRefId), std.set(obj.spec.parentRefs, gfRefId), gfRefId)
  ] + [
    // Ensure desired listeners on all target gateways
    esp.applyOptions(
      applyObjFromObj(gw) {
        spec: {
          listeners: [
            {
              name: 'https-%s-%s-%s' % [ h.namespace, h.name, h.pos ],
              hostname: h.hostname,
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
            for h in desiredListeners
            if secretName != ''
          ],
        },
      },
      fieldManager=httpRouteFieldManager(obj)
    )
    for gw in targetGws
  ] + [
    // Ensure finalizer and track parentRefs in annotation
    applyObjFromObj(obj) {
      metadata+: {
        finalizers: [ finalizer ],
        annotations+: {
          [parentRefTrackAnnotation]: std.manifestJsonMinified(obj.spec.parentRefs),
        },
      },
    },
  ]);

// cleanupAndRemoveFinalizer applies empty objects to all previously referenced gateways and to the HTTPRoute itself, removing all listeners and the finalizer.
// A empty object with the correct fieldManager is enough to remove fields we previously managed.
// Because the we set the fieldManager to the HTTPRoute specific one, we don't accidentally remove listeners created by other HTTPRoutes.
local cleanupAndRemoveFinalizer(obj) =
  local gateways = esp.context().gateways;
  local targetGws = [ gw for gw in gateways if std.member(obj.spec.parentRefs, gwRef(gw)) ];
  [
    esp.applyOptions(
      applyObjFromObj(gw),
      fieldManager=httpRouteFieldManager(obj)
    )
    for gw in targetGws
  ] + [
    applyObjFromObj(obj),
  ]
;

if esp.triggerName() == 'httproute' then
  local tdata = esp.triggerData();
  if tdata != null then (
    if !inDelete(tdata.resource) && wantsHttpsListener(tdata.resource) then
      ensureListenerAndFinalizer(tdata.resource)
    else
      cleanupAndRemoveFinalizer(tdata.resource)
  )
