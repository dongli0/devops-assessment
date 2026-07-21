# Shared Alibaba Cloud ALB

These cluster-scoped resources provide one shared public ALB for all five
portfolio environments.

## Ownership

- Terraform owns the VPC, vSwitches, and ACS cluster.
- The ALB Ingress Controller owns the ALB instance and its HTTP listener.
- Namespaced Ingress resources own the environment routing rules.

This avoids two control planes managing the same ALB listener.

## Rendering

Do not apply `albconfig.yaml.tmpl` directly.

The deployment pipeline reads the two vSwitch IDs from Terraform outputs and
renders the template:

```bash
export ALB_VSWITCH_ID_A="vsw-example-a"
export ALB_VSWITCH_ID_B="vsw-example-b"

envsubst '${ALB_VSWITCH_ID_A} ${ALB_VSWITCH_ID_B}' \
< albconfig.yaml.tmpl \
> /tmp/portfolio-albconfig.yaml
```

The pipeline must fail if the rendered file still contains `${...}`.

## Apply order

1. Render and apply the `AlbConfig`.
2. Wait until the ALB ID and DNS name are available.
3. Apply the `IngressClass`.
4. Apply the five environment overlays.

For teardown, delete the environment Ingress resources first, followed by the
IngressClass and AlbConfig, before destroying the VPC.
