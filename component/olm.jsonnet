local kube = import 'kube-ssa-compat.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local operatorlib = import 'lib/openshift4-operators.libsonnet';

// The hiera parameters for the component
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local airlock_xopenshift = import 'airlock-xopenshift.jsonnet';

local use_upgrade_controller = std.member(inv.applications, 'openshift-upgrade-controller') && params.olm.upgrade_strategy.manual_upgrade && params.olm.upgrade_strategy.upgrade_job_hook;
local params_upgrade_controller = inv.parameters.openshift_upgrade_controller;

// OLM Subscription
local operator_group = operatorlib.OperatorGroup('airlock-microgateway') {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-90',
    },
    namespace: params.namespace,
  },
};

local operator_subscription = operatorlib.namespacedSubscription(
  params.namespace,
  'airlock-microgateway',
  params.olm.channel,
  'certified-operators'
) {
  metadata+: {
    annotations+: {
      'argocd.argoproj.io/sync-wave': '-80',
    },
  },
  spec+: {
    [if params.olm.upgrade_strategy.manual_upgrade then 'installPlanApproval']: 'Manual',
    config+: {
      env: [
        {
          name: 'GATEWAY_API_POD_MONITOR_CREATE',
          value: '%s' % params.olm.config.create_pod_monitor,
        },
      ] + if params.airlock_xopenshift.enabled then [
        {
          name: 'GATEWAY_API_%s_API_GROUP' % airlock_xopenshift.enabled_crds[crd],
          value: airlock_xopenshift.api_group,
        }
        for crd in std.objectFields(airlock_xopenshift.enabled_crds)
      ] else [
      ],
    },
  },
};

// Upgrade Job Hook
local manual_approval_serviceaccount = {
  apiVersion: 'v1',
  kind: 'ServiceAccount',
  metadata: {
    name: 'airlock-microgateway-upgrade-approval',
    namespace: params_upgrade_controller.namespace,
  },
};

local manual_approval_role = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'Role',
  metadata: {
    name: 'airlock-microgateway-upgrade-approval',
    namespace: params.namespace,
  },
  rules: [
    {
      apiGroups: [ 'operators.coreos.com' ],
      resources: [ 'installplans' ],
      verbs: [ 'get', 'list', 'patch' ],
    },
  ],
};

local manual_approval_rolebinding = {
  apiVersion: 'rbac.authorization.k8s.io/v1',
  kind: 'RoleBinding',
  metadata: {
    name: 'airlock-microgateway-upgrade-approval',
    namespace: params.namespace,
  },
  roleRef: {
    apiGroup: 'rbac.authorization.k8s.io',
    kind: 'Role',
    name: manual_approval_role.metadata.name,
  },
  subjects: [
    {
      kind: 'ServiceAccount',
      name: manual_approval_serviceaccount.metadata.name,
      namespace: params_upgrade_controller.namespace,
    },
  ],
};

local manual_approval_configmap = {
  apiVersion: 'v1',
  kind: 'ConfigMap',
  metadata: {
    name: 'airlock-microgateway-upgrade-approval',
    namespace: params_upgrade_controller.namespace,
  },
  data: {
    approve: importstr './scripts/approve.sh',
  },
};

local manual_approval_upgradehook = {
  apiVersion: 'managedupgrade.appuio.io/v1beta1',
  kind: 'UpgradeJobHook',
  metadata: {
    name: 'airlock-microgateway-upgrade-approval',
    namespace: params_upgrade_controller.namespace,
  },
  spec: {
    selector: params.olm.upgrade_strategy.upgrade_job_selector,
    events: [ 'Create' ],
    template: {
      spec: {
        template: {
          spec: {
            restartPolicy: 'Never',
            priorityClassName: 'system-cluster-critical',
            serviceAccountName: manual_approval_serviceaccount.metadata.name,
            containers: [
              kube.Container('approve') {
                image: '$(registry)s/$(image)s:$(tag)s' % params.images.oc,
                command: [ '/usr/local/bin/approve' ],
                env_: {
                  AIRLOCK_NAMESPACE: params.namespace,
                },
                volumeMounts_: {
                  scripts: {
                    mountPath: '/usr/local/bin/approve',
                    subPath: 'approve',
                    readOnly: true,
                  },
                },
              },
            ],
            volumes: [
              {
                configMap: {
                  defaultMode: std.parseOctal('0550'),
                  name: manual_approval_configmap.metadata.name,
                },
                name: 'scripts',
              },
            ],
          },
        },
      },
    },
  },
};

if params.install_method == 'olm' then
  {
    '10_operator_group': operator_group,
    '10_operator_subscription': operator_subscription,
    [if use_upgrade_controller then '10_operator_upgradejobhook']: [
      manual_approval_serviceaccount,
      manual_approval_role,
      manual_approval_rolebinding,
      manual_approval_configmap,
      manual_approval_upgradehook,
    ],
  }
else
  {}
