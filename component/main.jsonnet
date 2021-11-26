// main template for openshift4-s3-forwarder
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.openshift4_s3_forwarder;
local app_name = inv.parameters._instance;

local serviceaccount = kube.ServiceAccount(app_name);

local configmap = kube.ConfigMap(app_name) {
  data: {
    'fluentd-loglevel': params.fluentd.loglevel,
    's3-bucket': params.s3.bucket,
    's3-endpoint': params.s3.endpoint,
    's3-interval': params.s3.interval,
    'td-agent.conf': |||
      <system>
        log_level "#{ENV['LOG_LEVEL']}"
      </system>
      <source>
        @type forward
        port 24224
        %(tls_config)s
        <security>
          shared_key "#{ENV['SHARED_KEY']}"
          self_hostname "#{ENV['HOSTNAME']}"
        </security>
      </source>
      <match **>
        @type s3
        <format>
          @type json
        </format>
        aws_key_id "#{ENV['S3_ACCESS_KEY']}"
        aws_sec_key "#{ENV['S3_SECRET_KEY']}"
        s3_bucket "#{ENV['S3_BUCKET']}"
        s3_endpoint "#{ENV['S3_ENDPOINT']}"
        path %(path)s
        time_slice_format %(format)s
        <buffer time>
          @type memory
          path /fluentd/log/s3/
          compress text
          chunk_limit_size 256m
          timekey "#{ENV['S3_INTERVAL']}"
          timekey_wait 1m
          timekey_use_utc true
        </buffer>
      </match>
    ||| % {
      path: '%Y-%m-%d/',
      format: '%Y-%m-%d_%H%M',
      tls_config: if params.fluentd.ssl.enabled then |||
        <transport tls>
          cert_path /secret/fluentd/tls.crt
          private_key_path /secret/fluentd/tls.key
          private_key_passphrase ""
        </transport>
      |||,
    },
  },
};

local secret = kube.Secret(app_name) {
  stringData: {
    access_key: params.s3.access_key,
    secret_key: params.s3.secret_key,
    shared_key: params.fluentd.sharedkey,
    [if params.fluentd.ssl.enabled then 'forwarder-tls.key']: params.fluentd.ssl.key,
    [if params.fluentd.ssl.enabled then 'forwarder-tls.crt']: params.fluentd.ssl.cert,
    [if params.fluentd.ssl.enabled then 'ca-bundle.crt']: params.fluentd.ssl.cert,
  },
};

local secret_splunk = kube.Secret(app_name + '-bucket') {
  data_:: {
    'splunk-ca.crt': params.splunk.ca,
  },
};

local statefulset = kube.StatefulSet(app_name) {
  spec+: {
    replicas: params.fluentd.replicas,
    template+: {
      spec+: {
        restartPolicy: 'Always',
        terminationGracePeriodSeconds: 30,
        serviceAccount: app_name,
        dnsPolicy: 'ClusterFirst',
        nodeSelector: params.fluentd.nodeselector,
        affinity: params.fluentd.affinity,
        tolerations: params.fluentd.tolerations,
        containers_:: {
          [app_name]: kube.Container(app_name) {
            image: params.images.fluentd.registry + '/' + params.images.fluentd.repository + ':' + params.images.fluentd.tag,
            resources: params.fluentd.resources,
            ports_:: {
              forwarder_tcp: { protocol: 'TCP', containerPort: 24224 },
              forwarder_udp: { protocol: 'UDP', containerPort: 24224 },
            },
            env_:: {
              NODE_NAME: { fieldRef: { apiVersion: 'v1', fieldPath: 'spec.nodeName' } },
              SHARED_KEY: { secretKeyRef: { name: app_name, key: 'shared_key' } },
              LOG_LEVEL: { configMapKeyRef: { name: app_name, key: 'fluentd-loglevel' } },
              S3_INTERVAL: { configMapKeyRef: { name: app_name, key: 's3-interval' } },
              S3_BUCKET: { configMapKeyRef: { name: app_name, key: 's3-bucket' } },
              S3_ENDPOINT: { configMapKeyRef: { name: app_name, key: 's3-endpoint' } },
              S3_ACCESS_KEY: { secretKeyRef: { name: app_name, key: 'access_key' } },
              S3_SECRET_KEY: { secretKeyRef: { name: app_name, key: 'secret_key' } },
            },
            livenessProbe: {
              tcpSocket: {
                port: 24224,
              },
              periodSeconds: 5,
              timeoutSeconds: 3,
              initialDelaySeconds: 10,
            },
            readinessProbe: {
              tcpSocket: {
                port: 24224,
              },
              periodSeconds: 3,
              timeoutSeconds: 2,
              initialDelaySeconds: 2,
            },
            terminationMessagePolicy: 'File',
            terminationMessagePath: '/dev/termination-log',
            volumeMounts_:: {
              buffer: { mountPath: '/fluentd/log/' },
              'fluentd-config': { readOnly: true, mountPath: '/fluentd/etc' },
              [if params.fluentd.ssl.enabled then 'fluentd-certs']:
                { readOnly: true, mountPath: '/secret/fluentd' },
            },
          },
        },
        volumes_:: {
          buffer:
            { emptyDir: {} },
          'fluentd-config':
            { configMap: { name: app_name, items: [ { key: 'td-agent.conf', path: 'fluent.conf' } ], defaultMode: 420, optional: true } },
          [if params.fluentd.ssl.enabled then 'fluentd-certs']:
            { secret: { secretName: app_name, items: [ { key: 'forwarder-tls.crt', path: 'tls.crt' }, { key: 'forwarder-tls.key', path: 'tls.key' } ] } },
        },
      },
    },
  },
};

local service = kube.Service(app_name) {
  target_pod:: statefulset.spec.template,
  target_container_name:: app_name,
  spec+: {
    sessionAffinity: 'None',
  },
};


// Define outputs below
{
  '11_serviceaccount': serviceaccount,
  '12_configmap': configmap,
  '13_secret': secret,
  '21_statefulset': statefulset,
  '22_service': service,
}
