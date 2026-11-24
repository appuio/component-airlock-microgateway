local kap = import 'lib/kapitan.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local mrName = 'backendtlspolicy-cnp';
local saName = 'espejote-btlspolicy-cnp';

// Rendered CNPs are named sha256(service-name)[:20] + '-' + service-name, so several
// instances watching the same source namespace produce the same names in different
// (their own) target namespaces; GC is label+namespace scoped, so they never interfere.
local template = |||
  local esp = import 'espejote.libsonnet';

  local sniEnabled(svc) =
    std.get(std.get(svc.metadata, 'labels', {}), 'microgateway.vshn.io/enable-sni-check', 'true') != 'false';
  local portsFor(ref, svc) =
    if std.objectHasAll(ref, 'sectionName') && ref.sectionName != null && ref.sectionName != '' then
      [ p for p in svc.spec.ports if std.objectHasAll(p, 'name') && p.name == ref.sectionName ]
    else svc.spec.ports;

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

  local cnpBody(svc, egress) =
    local hash = std.substr(std.sha256(svc.metadata.name), 0, 20);
    local hashed = hash + '-' + std.substr(svc.metadata.name, 0, 63 - std.length(hash) - 1);
    {
      apiVersion: 'cilium.io/v2',
      kind: 'CiliumNetworkPolicy',
      metadata: {
        name: if std.endsWith(hashed, '-') then std.substr(hashed, 0, std.length(hashed) - 1) else hashed,
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

  local dnsCnp(svc) =
    local ports = std.get(svc.spec, 'ports', []);
    local emptyServerNames = [];
    cnpBody(svc, [ egressEntry(svc, ports, emptyServerNames) ]);

  local policyCnp(svc, binds) =
    local entries = [
      egressEntry(svc, portsFor(b.ref, svc), if sniEnabled(svc) then [ b.hostname ] else [])
      for b in binds
      if std.objectHasAll(svc.spec, 'ports') && std.length(portsFor(b.ref, svc)) > 0
    ];
    local pruneThisCNP = null;
    if std.length(entries) == 0 then pruneThisCNP else cnpBody(svc, entries);

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
  local defaultConfig = std.get(params.default, 'backendTLSPolicyCNP', {});
  local instanceConfig = std.get(params.instances[instanceName], 'backendTLSPolicyCNP', {});
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

local instanceObjects(instanceName) =
  local cfg = config(instanceName);
  assert std.isString(cfg.sourceNamespace) && cfg.sourceNamespace != '' : 'backendTLSPolicyCNP.sourceNamespace must be set for enabled instance ' + instanceName;
  local gateway = instanceName;
  local source = cfg.sourceNamespace;
  local sourceRoleName = '%s-%s' % [ saName, gateway ];
  assert std.isString(cfg.apiVersion) && std.findSubstr('/', cfg.apiVersion) != [] : 'backendTLSPolicyCNP.apiVersion must be a group/version string for enabled instance ' + instanceName;
  local policyAPIVersion = cfg.apiVersion;
  local policyGroup = std.split(policyAPIVersion, '/')[0];
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
              apiVersion: policyAPIVersion,
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
    role(sourceRoleName, source, [
      {
        apiGroups: [ '' ],
        resources: [ 'services' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
      {
        apiGroups: [ policyGroup ],
        resources: [ 'backendtlspolicies' ],
        verbs: [ 'get', 'list', 'watch' ],
      },
    ]),
    // The Role and its binding are named per-instance: one Role per instance
    // lives in the shared source namespace.
    roleBinding(sourceRoleName, source, sourceRoleName, gateway),
  ];

{
  // Every object a single gateway instance needs, or [] when the feature is off.
  forInstance(instanceName):: if config(instanceName).enabled then instanceObjects(instanceName) else [],
}
