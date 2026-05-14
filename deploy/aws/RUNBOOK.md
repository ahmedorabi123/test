# AWS Lightsail Single-Instance Runbook

Target: one Lightsail instance running Postgres + Rails + Caddy via Docker
Compose. Region default: `eu-west-1`.

## 1. Provision instance

1. Lightsail console → Create instance → Linux/Ubuntu 22.04 → `medium_2_0`
   plan or higher.
2. Open firewall ports `80`, `443` (HTTP/HTTPS). SSH (`22`) is already open.
3. Allocate a static IP and attach it. Note the IP.
4. DNS: create an `A` record `erp.example.com → <static-ip>`.

## 2. Push images

Build & push from CI (or locally):

```sh
docker build -f backend/Dockerfile -t ghcr.io/your-org/shopify_erp_2-backend:latest backend
docker push ghcr.io/your-org/shopify_erp_2-backend:latest
```

Build the frontend dist locally and copy it to the instance under
`./frontend-dist` next to `compose.production.yml`:

```sh
cd frontend && npm ci && npm run build
scp -r dist/* ubuntu@<ip>:/opt/shopify_erp_2/frontend-dist/
```

## 3. Bootstrap the instance

```sh
ssh ubuntu@<ip>
git clone <this repo>
cd shopify_erp_2/deploy/aws
cp .env.production.example /opt/shopify_erp_2/.env.production
# edit secrets…
bash setup.sh
```

`setup.sh` is idempotent. First run will exit after creating
`.env.production`; edit, then re-run.

## 4. Migrate + seed

```sh
docker compose -f deploy/aws/compose.production.yml exec backend bin/rails db:prepare
docker compose -f deploy/aws/compose.production.yml exec backend bin/rails db:seed
```

## 5. Verify

```sh
bash deploy/aws/healthcheck.sh https://erp.example.com/up
```

Caddy obtains a Let's Encrypt cert automatically on first HTTPS request to a
real domain. Wildcard / staging? Override the Caddyfile.

## 6. Backups

* `docker compose -f deploy/aws/compose.production.yml exec backend bin/rake db:backup`
* Lightsail snapshot (block-device level) once per day.

## 7. Updating

```sh
docker compose -f deploy/aws/compose.production.yml pull backend
docker compose -f deploy/aws/compose.production.yml up -d
```

Solid Queue runs in the Puma plugin; no separate worker bounce required.

## 8. Destructive Shopify reset

If you need to wipe Shopify-origin data while keeping manual ERP data:

```sh
docker compose -f deploy/aws/compose.production.yml exec \
  -e CLEANUP_CONFIRM=YES_I_MEAN_IT -e DRY_RUN=1 \
  backend bin/rake db:cleanup:shopify_only

# review counts, then re-run without DRY_RUN:
docker compose -f deploy/aws/compose.production.yml exec \
  -e CLEANUP_CONFIRM=YES_I_MEAN_IT \
  backend bin/rake db:cleanup:shopify_only
```
