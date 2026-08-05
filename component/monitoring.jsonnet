local kube = import 'kube-ssa-compat.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local prom = import 'lib/prom.libsonnet';
local main = import 'main.jsonnet';

local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway.monitoring;
local backendImage = inv.parameters.airlock_microgateway.images.nginx;
local nsName = params.namespace.metadata.name;
local has(obj, field) = std.objectHas(obj, field) && obj[field] != null;

local namespace(override={}) = kube.Namespace(nsName) {} + (
  if has(override, 'labels') || has(override, 'annotations')
  then
    {
      metadata+: com.makeMergeable(params.namespace.metadata),
    }
  else {}
);

local backendNetworkPolicy(name) = kube.NetworkPolicy(name) {
  metadata+: {
    namespace: 'vshn-airlock-monitoring',
  },
  spec: {
    ingress: [ {
      from: [ {
        namespaceSelector: {
          matchLabels: {
            'appuio.ch/waf': 'airlock',
          },
        },
      } ],
    } ],
    podSelector: {
      matchLabels: {
        app: 'microgateway-monitoring',
      },
    },
    policyTypes: [
      'Ingress',
    ],
  },
};
local backendConfigMap = kube.ConfigMap('nginx-conf') {
  metadata+: {
    namespace: nsName,
  },
  data: params.dummyBackend.configMap.data,
};
local backendDeployment = kube.Deployment('microgateway-canary-backend') {
  metadata+: {
    namespace: nsName,
    labels: {
      app: 'microgateway-monitoring',
    },
  },
  spec+: {
    template+: {
      spec+: {
        containers: [
          {
            name: 'nginx',
            image: backendImage.registry + '/' + backendImage.repository + ':' + backendImage.tag,
            resources: params.dummyBackend.resources,
            ports: [
              {
                name: 'http',
                containerPort: 8080,
              },
            ],
            livenessProbe: {
              httpGet: {
                port: 'http',
                path: '/health',
              },
            },
            volumeMounts: [ {
              mountPath: '/etc/nginx/conf.d/default.conf',
              name: 'nginx-conf',
              subPath: 'default.conf',
            } ],
          },
        ],
        volumes+: [ {
          name: 'nginx-conf',
          configMap: {
            name: 'nginx-conf',
          },
        } ],
      },
    },
  },
};
local backendService = kube.Service('microgateway-canary-backend-svc') {
  target_pod:: backendDeployment.spec.template,
  target_container_name:: 'nginx',
  metadata+: {
    name: 'airlock-microgateway-rules',
    namespace: nsName,
  },
};
local httpRoute(name='') = {
  apiVersion: 'gateway.networking.k8s.io/v1',
  kind: 'HTTPRoute',
  metadata: {
    namespace: name,
    name: name,
  },
  spec: {},
};
local contentSecurityPolicy(name='') = {
  apiVersion: 'microgateway.airlock.com/v1alpha1',
  kind: 'ContentSecurityPolicy',
  metadata+: {
    name: 'monitoring-routes-content-security-policy',
    namespace: nsName,
  },
  spec: params.contentSecurityPolicySpec,
};

local httpRoutes = {
  ['monitoring/HttpRoutes/%s' % instance.metadata.name]: instance
  for instance in com.generateResources(params.httpRoutes, httpRoute)
};

local promRules = {}
                  + (if params.sessionMonitoring.enabled then params.sessionMonitoring.rules else {})
                  + (if params.blackboxExporter.enabled then params.blackboxExporter.rules else {});

local prometheusRule = prom.generateRules('airlock-microgateway-rules', promRules) {
  metadata+: {
    name: 'airlock-microgateway-rules',
    namespace: nsName,
  },
};
local hasGroup = std.length(prometheusRule.spec.groups) > 0;

local backendResources =
  if params.dummyBackend.enabled then {
    'monitoring/Backend/configMap': backendConfigMap,
    'monitoring/Backend/networkPolicy':
      backendNetworkPolicy('allow-gateways'),
    'monitoring/Backend/Deployment': backendDeployment,
    'monitoring/Backend/Service': backendService,
  } else {};

local httpRouteResources =
  if has(params, 'httpRoutes') then
    httpRoutes {
      'monitoring/HttpRoutes/contentSecurityPolicy':
        contentSecurityPolicy('monitoring'),
    }
  else
    {};

if params.enabled then (
  {
    'monitoring/Namespace': namespace(params.namespace.metadata),
    [if hasGroup then 'monitoring/Prometheusrule']:
      prometheusRule,
  }
  + backendResources
  + httpRouteResources
) else {}
