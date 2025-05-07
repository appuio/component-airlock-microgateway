local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.airlock_microgateway;

local helm_values = params.helm_values;

// local helm_values = {
//   operator: {
//     gatewayAPI: {
//       enabled: true,
//       podMonitor: {
//         create: true,
//         labels: {
//           release: 'kube-prometheus-stack',
//         },
//       },
//     },
//     serviceMonitor: {
//       create: true,
//       labels: {
//         release: 'kube-prometheus-stack',
//       },
//     },
//   },
//   dashboards: {
//     create: true,
//   },
// };

{
  values: helm_values,
}
