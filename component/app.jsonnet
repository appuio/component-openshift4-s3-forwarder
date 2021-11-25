local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.openshift4_s3_forwarder;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('openshift4-s3-forwarder', params.namespace);

{
  'openshift4-s3-forwarder': app,
}
