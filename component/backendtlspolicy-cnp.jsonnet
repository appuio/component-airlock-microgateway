// Renders one Espejote ManagedResource per gateway instance (when enabled) that turns
// BackendTLSPolicies + ExternalName Services in a configurable source namespace into
// CiliumNetworkPolicies in the gateway instance namespace.
local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local mrName = 'backendtlspolicy-cnp';
local saName = 'espejote-btlspolicy-cnp';

// Rendered CNPs are named md5(service-name)[:20], so several instances watching the
// same source namespace produce the same names in different (their own) target
// namespaces; GC is label+namespace scoped, so they never interfere.
local template = |||
  local esp = import 'espejote.libsonnet';

  local sniDisabled(svc) =
    std.get(std.get(svc.metadata, 'labels', {}), 'microgateway.airlock.com/enable-sni-check', '') == 'false';
  local portsFor(ref, svc) =
    if std.objectHasAll(ref, 'sectionName') && ref.sectionName != null && ref.sectionName != '' then
      [ p for p in svc.spec.ports if std.objectHasAll(p, 'name') && p.name == ref.sectionName ]
    else svc.spec.ports;

  // One pass over every policy's usable core-Service refs: maps Service name
  // -> [{hostname, ref}] bindings in policy-then-ref order. No per-service rescan.
  local bindingsByService(policies) =
    std.foldl(
      function(acc, b)
        acc { [b.svc]: std.get(acc, b.svc, []) + [ { hostname: b.hostname, ref: b.ref } ] },
      [
        { svc: ref.name, hostname: policy.spec.validation.hostname, ref: ref }
        for policy in policies
        for ref in policy.spec.targetRefs
        if ref.kind == 'Service' && ref.group == ''
      ],
      {}
    );

  // CNP shell shared by both classes: hash-named metadata (first 20 hex of
  // md5 of the Service name; source Service kept in an annotation) with the
  // distinctive label, the gateway instance's endpointSelector, and the
  // egress list.
  local cnpBody(svc, egress) = {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      name: std.substr(std.md5(svc.metadata.name), 0, 20),
      namespace: '%(target)s',
      labels: { 'espejote.io/managed-resource': '%(label)s' },
      annotations: { 'espejote.io/source-service': svc.metadata.name },
    },
    spec: {
      endpointSelector: {
        matchLabels: { 'gateway.networking.k8s.io/gateway-name': '%(gateway)s' },
      },
      egress: egress,
    },
  };
  // Egress entry shape shared by both classes: toFQDNs for the externalName,
  // toPorts narrowing when there are ports, serverNames only for the SNI class.
  // Portless Service -> unrestricted toFQDNs-only entry.
  local egressEntry(svc, ports, serverNames) =
    { toFQDNs: [ { matchName: svc.spec.externalName } ] }
    + (if std.length(ports) == 0 then {} else {
         toPorts: [ {
           ports: [
             { port: '' + p.port, protocol: p.protocol }
             for p in ports
           ],
         } + (if std.length(serverNames) == 0 then {} else { serverNames: serverNames }) ],
       });

  // DNS class -- a Service referenced by NO BackendTLSPolicy: an unrestricted
  // egress entry to the externalName over ALL its declared ports, no SNI.
  local dnsCnp(svc) =
    cnpBody(svc, [ egressEntry(svc, std.get(svc.spec, 'ports', []), []) ]);

  // Referenced class -- a policy's targetRef points at this Service: ports come
  // from the targetRef (sectionName subset, or all Service ports when the ref
  // omits sectionName). SNI is enforced via serverNames UNLESS the Service opts
  // out (microgateway.airlock.com/enable-sni-check: "false") -- then it is still
  // the policy's ports, just DNS-checked instead of SNI-checked. Zero surviving
  // ports -> null (the prune path).
  local policyCnp(svc, binds) =
    local entries = [
      egressEntry(svc, portsFor(b.ref, svc), if sniDisabled(svc) then [] else [ b.hostname ])
      for b in binds
      if std.objectHasAll(svc.spec, 'ports') && std.length(portsFor(b.ref, svc)) > 0
    ];
    if std.length(entries) == 0 then null else cnpBody(svc, entries);

  local cnpFor(svc, binds) =
    if std.length(binds) == 0 then dnsCnp(svc) else policyCnp(svc, binds);
  local ctx = esp.context();
  local byService = bindingsByService(ctx.backendtlspolicies);
  local rendered = [
    cnpFor(svc, std.get(byService, svc.metadata.name, []))
    for svc in ctx.services
    if std.objectHasAll(svc.spec, 'externalName')
  ];

  local desiredNames = [ r.metadata.name for r in rendered if r != null ];
  local stale = [
    c
    for c in ctx.ciliumnetworkpolicies
    if !std.member(desiredNames, c.metadata.name)
  ];
  rendered + [ esp.markForDelete(c) for c in stale ]
|||;

local config(instanceName) =
  local defaultConfig = if std.objectHas(params.default, 'backendTLSPolicyCNP') then params.default.backendTLSPolicyCNP else {};
  local instanceConfig = if std.objectHas(params.instances[instanceName], 'backendTLSPolicyCNP') then params.instances[instanceName].backendTLSPolicyCNP else {};
  std.mergePatch(defaultConfig, instanceConfig);

local role(name, namespace, rules) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: { name: name, namespace: namespace },
  rules: rules,
};

local roleBinding(name, namespace, roleName, saNamespace) = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: { name: name, namespace: namespace },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: roleName,
  },
  subjects: [ {
    kind: 'ServiceAccount',
    name: saName,
    namespace: saNamespace,
  } ],
};

local objects(instanceName) =
  local cfg = config(instanceName);
  assert std.isString(cfg.sourceNamespace) && cfg.sourceNamespace != '' : 'backendTLSPolicyCNP.sourceNamespace must be set for enabled instance ' + instanceName;
  local gateway = instanceName;
  local source = cfg.sourceNamespace;
  [
    {
      apiVersion: 'espejote.io/v1alpha1',
      kind: 'ManagedResource',
      metadata: { name: mrName, namespace: gateway },
      spec: {
        context: [
          {
            name: 'services',
            resource: { apiVersion: 'v1', kind: 'Service', namespace: source },
          },
          {
            name: 'backendtlspolicies',
            resource: {
              apiVersion: 'x-openshift.microgateway.airlock.com/v1alpha3',
              kind: 'BackendTLSPolicy',
              namespace: source,
            },
          },
          {
            name: 'ciliumnetworkpolicies',
            resource: {
              apiVersion: 'cilium.io/v2',
              kind: 'CiliumNetworkPolicy',
              namespace: gateway,
              labelSelector: { matchLabels: { 'espejote.io/managed-resource': mrName } },
            },
          },
        ],
        triggers: [
          { name: 'backendtlspolicy', watchContextResource: { name: 'backendtlspolicies' } },
          { name: 'service', watchContextResource: { name: 'services' } },
        ],
        serviceAccountRef: { name: saName },
        template: template % { target: gateway, gateway: gateway, label: mrName },
      },
    },
    {
      apiVersion: 'v1',
      kind: 'ServiceAccount',
      metadata: { name: saName, namespace: gateway },
    },
    role(saName, gateway, [
      {
        apiGroups: [ 'cilium.io' ],
        resources: [ 'ciliumnetworkpolicies' ],
        verbs: [ 'get', 'list', 'watch', 'create', 'patch', 'delete' ],
      },
    ]),
    roleBinding(saName, gateway, saName, gateway),
    role(saName, source, [
      {
        apiGroups: [ '' ],
        resources: [ 'services' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
      {
        apiGroups: [ 'x-openshift.microgateway.airlock.com' ],
        resources: [ 'backendtlspolicies' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
    ]),
    // The binding lives in the source namespace and is per-instance because its
    // subject (the SA) lives in the instance's gateway namespace.
    roleBinding('%s-%s' % [ saName, gateway ], source, saName, gateway),
  ];

{
  ['backendtlspolicy-cnp/%s/%s/%s-%s' % [ i.key, object.metadata.namespace, object.kind, object.metadata.name ]]: object
  for i in std.objectKeysValues(params.instances)
  if config(i.key).enabled
  for object in objects(i.key)
}
