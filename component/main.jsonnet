// main template for openshift4-s3-forwarder
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_s3_forwarder;

// Define outputs below
{
}
