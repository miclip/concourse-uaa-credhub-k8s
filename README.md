## Deploy Concourse with Credhub and UAA oauth

### Components 

1. cert-manager with `Let’s Encrypt` issuers
2. contour
3. UAA 
4. Credhub with UAA oauth delegation 
5. Concourse with UAA oauth delegation 

### Deploy

~~~sh
git clone git@github.com:miclip/concourse-uaa-credhub-k8s.git
cd ./concourse-uaa-credhub-k8s

# Update `values.yaml` with at least domain details. 

./deploy-all.sh 
~~~

Deploy script will print the ingress IP/DNS that needs to be setup within external DNS e.g. *.ci.mydomain.io. 

> Note: `Let’s Encrypt` can take a while to issue certs, run `kubectl get certificates -n concourse` and they all should be READY. Have seen it take upwards of an hour. 

### Test 

Test pipeline to verify concourse credhub integration: 

~~~sh 
credhub login -s https://credhub.mydomain.io -u credhub -p password --skip-tls-validation
credhub set -n /concourse/main/mysecret -v mike -t value
credhub get -n /concourse/main/mysecret 
~~~

~~~yaml
jobs:
- name: hello-world-job
  plan:
  - task: hello-world-task
    params:
      SECRET_TEST: ((mysecret))
    config:
      platform: linux
      parms:
        SECRET_TEST:
      image_resource:
        type: registry-image
        source:
          repository: busybox 
      run:
        path: sh
        args:
        - -ec
        - |
          echo "HELLO WORLD ${SECRET_TEST}"
~~~

~~~sh 
fly login -t my-main -c https://concourse.mydomain.io -k -b -n main
fly -t my-main sp -p hello-world -c ./hello-world.yml
fly -t my-main unpause-pipeline -p hello-world
fly -t miclip-main trigger-job -j hello-world/hello-world-job -w
~~~

Should expect: 
~~~sh 
started hello-world/hello-world-job #2

initializing
selected worker: concourse-worker-0
selected worker: concourse-worker-0
selected worker: concourse-worker-1
running sh -ec echo "HELLO WORLD ${SECRET_TEST}"

HELLO WORLD mike
~~~

### Known Issues

1. UAA authorize POST is using HTTP and you'll get an alert when authorizing the client. Still investigating...
