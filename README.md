# Rings

Ring deployment is a configuration on top of a service deployment that allows you to deploy *revisions* of the service alongside any existing instances of *that* service, and any other services. It allows you to control the "blast radius" of a change to a service by gradually rolling out new revisions of a microservice to production without the risk of affecting all end users.

This README serves to explain a ring based deployment using [Fabrikate](https://github.com/microsoft/fabrikate) and Bedrock.

**NOTE**: This pipeline is ideal for developers who want to practice Bedrock GitOps **without using a Service Mesh**. This approach will require that you have an application that replicates the behavior of a Service Mesh (e.g. [Ring Operator](https://github.com/microsoft/ring-operator)).

The ring workflow is shown in the following diagram, where you see that it represents an extension to the [Bedrock CI/CD](https://github.com/microsoft/bedrock/tree/master/gitops).

![Ring Workflow](./images/ring-workflow.png)

In summary, there are three major changes made to the Bedrock CI/CD to account for this rings implementation:

1. Add ring.yaml (template) to Helm Charts
2. Create ring path in the Source Repository
3. Restructure the Cluster HLD Repository

## Components of the Ring Model

### Git Repositories

Recall that in the official Bedrock CI/CD (without rings), there exists three types of repositories: (1) Service Source Code (2) HLD and (3) the Materialized. In a ring model,the same repositories exists as well. The following repositories are required in the rings workflow:

**Service Source Repository**: A git repository that maintains the source code of the service, a dockerfile, and a helm chart. Developers will commit regularly to this repository, with revisions and rings being tracked in Git branches.

For all services represented by git repositories, we assume three more repositories exist:

**Helm Chart Repository**: A git repository to store Helm packages or charts for the service(s).

**Cluster HLD Repository**: A git repository that maintains a High Level Definition for all Services and Revisions that are intended to be run on the Cluster.

**“Materialized” Manifest Repository**: this git repository acts as our canonical source of truth for Flux – the in-cluster component that pulls and applies Kubernetes manifests rendered from the Cluster HLD repository.

### Ring Yaml
As a ring is considered to be strictly a revision of a microservice, we need a way to configure the ingress controller to route to the microservice revision a user belongs to. We achieve this by providing a `ring.yaml` in our helm chart, which is an abstraction on Kubernetes and Traefik primitives.

An example of the `ring.yaml` template:

```yaml
# Source: hello-ring/templates/ring.yaml
apiVersion: rings.microsoft.com/v1alpha1
kind: Ring
metadata:
  name: {{.Values.serviceName}}-{{.Values.majorVersion}}-{{ .Values.ringName }}
  contact: {{ .Values.contact }}
  branchName: {{ .Values.branchName }} # Set by pipeline
  buildId: {{ .Values.buildId }} # Set by pipeline
  buildDate: {{ .Values.buildDate }} # Set by pipeline
  commitId: {{ .Values.commitId }} # Set by pipeline
spec:
  # Deploy to environment
  deploy: {{ .Values.deploy }}
  entryPoints:
    # Source of traffic (eg: 80 or 443)
    - http
    - https
    - internal
  routing:
    service: {{ .Values.serviceName }}
    version: {{ .Values.majorVersion }}
    branch: {{ .Values.branch }}
    group: {{ .Values.group }}
    ports:
      {{- range .Values.application.ports }}
      - {{ . }}
      {{- end }}
    initialUsers:
      {{- range .Values.initialUsers }}
      - {{ . }}
      {{- end }}
```

The `ring.yaml` will consume values from the `values.yaml` (if present), and most importantly, from the `common.yaml` that is created and held in the ring path of the Service Source repo. The `common.yaml` should be configured to modify the ring specs of the `ring.yaml`. An example of the ring `common.yaml`:

```yaml
config:
  serviceName: "hello-rings"
  majorVersion: "v1"
  ringName: "master"
  group: "CORE"
  contact: admin@hellorings.com
```

A `ring` folder in the Source repo should be created to store the `common.yaml` and a `component.yaml`, as shown:

**Source Repository**:
 * **ring**
   * config
       * **common.yaml**
   * **component.yaml**
 * src
   * Dockerfile
   * ..
 * azure-pipelines.yaml

 The `component.yaml` will source the Helm Chart Repo for the service, and the `common.yaml` will provide the values to the `ring.yaml`.

### Ring Operator
The ring.yaml is consumed by a custom resource controller, which we call the Ring Controller. The Ring Controller sets up two resources on the cluster that map traffic to the proper service revision: a Traefik Ingress Route that maps path and headers to a Kubernetes service, and a Kubernetes service that maps to the microservice deployment. Microsoft has an open-sourced Ring Operator that is compatible with the Bedrock Rings Model. For more information, please visit [here](https://github.com/microsoft/ring-operator).

## Adding a Service to the Ring Model

It is very common to manage multiple services or microservices in Bedrock, and in order to account for that in the ring model, the Cluster HLD repository is structured in the following way:

**Cluster HLD Repository**:
 * ServiceA
   * config
       * common.yaml
   * component.yaml
 * ServiceB
   * config
       * common.yaml
   * component.yaml
 * azure-pipelines.yaml
 * component.yaml

 The **root** `component.yaml` file should resemble the following:

 ```yaml
name: hello-rings-cluster
subcomponents:
- name: hello-rings
  type: component
  source: hello-rings
- name: ring-operator
  type: component
  source: ring-operator
```

Each service or microservice is a subcomponent, and is mapped to a service path/folder in the HLD repo (e.g. `source: hello-rings`).

When adding a new service to the rings workflow, the developer will need to:
  1. Update the **root** `component.yaml` by adding a new subcomponent for the service.
  2. Add a new path (folder) in the Cluster HLD Repo that associates to that service. The folder should include a `component.yaml` that sources the serivce and all of its rings (git branches):

  ```yaml
  name: hello-rings
  type: component
  subcomponents:
  - name: hello-rings-featurea
    type: helm
    source: https://github.com/bnookala/hello-rings
    method: git
    path: ring
    branch: featurea
  - name: hello-rings-featureb
    type: helm
    source: https://github.com/bnookala/hello-rings
    method: git
    path: ring
    branch: featureb
  ```

## Creating a New Ring for a Service

This section will assist in understanding the order of operations of a ring model. However, if you want a step-by-step guide on implementing rings, please visit the [Rings Implementation Guide](https://github.com/microsoft/bedrock-rings/blob/master/docs/RingsImplementation.md)

### 1. Create a New Branch

To create a revision of the microservice that can deploy alongside existing instances of the microservice, and any other microservices, a developer will need to create a new git branch on the microservice source repository. The git branch could reflect a bug fix or a new feature for the service, but regardless, should be a revision of some kind with a unique ring definition (e.g. branch name, ring.yaml).

### 2. Image Tag Release Pipeline

The [Image Tag Release Pipeline](https://github.com/microsoft/bedrock/blob/master/gitops/azure-devops/ImageTagRelease.md), which is a core component of the Bedrock CI/CD workflow,will acknowledge the creation of a new ring when a git branch is created. Like any other commit, it will trigger the build for the Image Tag Release process. Recall that this will execute a Build Pipeline to build and push a Docker image using the new image tag. Then, it will initiate the Release pipeline, where a Pull Request will be created to (1) have Fabrikate update the image tag (along with other metadata) in the **service Fabrikate definitions** (e.g. config/common.yaml), (2) add a new subcomponent (via `fab add` command) to the **service** `component.yaml` (shown below).

### 3. Merge Pull Request against Service HLD Repo

A developer on a project must manually engage a Pull Request merge in order to gate access for a ring to production.

### 4. Manifest Generation Pipeline

When the pull request is merged by a developer into the `master` branch of the Cluster HLD repository, the [Manifest Generation Pipeline](https://github.com/microsoft/bedrock/blob/master/gitops/azure-devops/ManifestGeneration.md) initiates. The Manifest Generation pipeline will source all known services that are intended to be run on a cluster via their representative HLD paths within the Cluster HLD repo.

## References

- [Service Source Repo](https://github.com/bnookala/hello-rings)
- [Helm Chart Repo](https://github.com/bnookala/hello-rings-helm)
- [Cluster HLD Repo](https://github.com/bnookala/hello-rings-cluster-v2)
- [Materialized Manifest Repo](https://github.com/bnookala/hello-rings-cluster-materialized)
- [Ring Operator](https://github.com/microsoft/ring-operator)
