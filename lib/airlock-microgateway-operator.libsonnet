/**
 * \file Library with public methods provided by component airlock-microgateway-operator.
 */

local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

/**
 * The main Gateway API K8s API group
 */
local gateway_group = 'gateway.networking.k8s.io';
/**
 * The main Airlock Microgateway K8s API group
 */
local airlock_group = 'microgateway.airlock.com';
/**
 * The Airlock Microgateway K8s API group for temporary copies of upstream
 * Gateway AP resources
 */
local xopenshift_group = 'x-openshift.microgateway.airlock.com';

/**
 * Helper function to create Airlock Microgateway GatewayParameters resources
 *
 * \arg name used as `metadata.name`
 * \returns a partial `GatewayParameters` object
 */
local GatewayParameters = function(name='') {
  apiVersion: '%s/v1alpha1' % airlock_group,
  kind: 'GatewayParameters',
  metadata: {
    name: name,
  },
};

/**
 * Helper function to create Gateway API GatewayClass resources
 *
 * \arg name used as `metadata.name`
 * \returns a partial `GatewayClass` object
 */
local GatewayClass = function(name='') {
  apiVersion: '%s/v1' % gateway_group,
  kind: 'GatewayClass',
  metadata: {
    name: name,
  },
};

/**
 * Helper function to create Gateway API Gateway resources
 *
 * \arg name used as `metadata.name`
 * \returns a partial `Gateway` object
 */
local Gateway = function(name='') {
  apiVersion: '%s/v1' % gateway_group,
  kind: 'Gateway',
  metadata: {
    name: name,
  },
};

{
  GatewayParameters: GatewayParameters,
  GatewayClass: GatewayClass,
  Gateway: Gateway,

  gatewayApiGroup: gateway_group,
  airlockApiGroup: airlock_group,
  xopenshiftApiGroup: xopenshift_group,
}
