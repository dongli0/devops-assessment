# Shared Alibaba Cloud ALB

These cluster-scoped resources provide one shared public ALB for all five
portfolio environments.

## Ownership

- Terraform owns the VPC, vSwitches, and ACS cluster.
- The ALB Ingress Controller owns the ALB instance and HTTP listener.
- Namespaced Ingress resources own the environment routing rules.

This avoids two control planes managing the same ALB listener.

## Controller Prerequisite

Install the ALB Ingress Controller in **Do not create** mode. Do not allow the
add-on installer to create its default `alb` AlbConfig, IngressClass, and
billable ALB because this repository creates the shared `alb-shared` platform.

Before rendering the platform, these commands should produce no output:

```bash
kubectl get albconfig alb --ignore-not-found
kubectl get ingressclass alb --ignore-not-found
```

If either resource exists, stop and resolve its ownership before creating
`alb-shared`. See the
[Alibaba Cloud controller documentation](https://help.aliyun.com/zh/cs/user-guide/manage-the-alb-ingress-controller-1).

## Rendering

Do not apply `albconfig.yaml.tmpl` directly. Run the renderer from the repository
root with vSwitch IDs and zones obtained from Terraform outputs:

```bash
export ALB_VSWITCH_ID_A="vsw-examplea"
export ALB_VSWITCH_ID_B="vsw-exampleb"
export ALB_VSWITCH_ZONE_A="cn-shanghai-e"
export ALB_VSWITCH_ZONE_B="cn-shanghai-f"

./scripts/render-alb-config.sh \
  > /tmp/portfolio-albconfig.yaml
```

The renderer rejects:

- missing or malformed vSwitch IDs;
- duplicate vSwitch IDs;
- vSwitches assigned to the same zone;
- unresolved template placeholders;
- rendered output that does not contain exactly two vSwitch IDs.

Zone values are validation inputs and are not written to the AlbConfig.

The directory Kustomization intentionally contains only `IngressClass`. This
prevents `kubectl apply -k` from applying an unresolved AlbConfig template.

## Apply Order

1. Confirm that no installer-owned default `alb` resources exist.
2. Render `/tmp/portfolio-albconfig.yaml`.
3. Validate it against the installed CRD:

   ```bash
   kubectl apply --dry-run=server \
     -f /tmp/portfolio-albconfig.yaml
   ```

4. Apply the rendered AlbConfig:

   ```bash
   kubectl apply -f /tmp/portfolio-albconfig.yaml
   ```

5. Wait until the AlbConfig reports the ALB ID and DNS name.
6. Apply the repository-owned IngressClass:

   ```bash
   kubectl apply -k deploy/platform/alicloud-alb/cluster
   ```

7. Apply the five environment overlays.

For teardown, delete the environment Ingress resources first, followed by the
IngressClass and AlbConfig, before destroying the VPC.
