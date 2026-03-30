# GCP Demo App

A minimal Node.js web app built for Google Cloud deployment scenarios.
Zero npm dependencies — runs with Node's built-in `http` module.

## Project Structure

```
gcp-demo-app/
├── server.js            # Main HTTP server
├── public/
│   └── index.html       # UI (live metadata, endpoint list)
├── Dockerfile           # Multi-stage Docker build
├── .dockerignore
├── package.json
├── app-flex.yaml        # Q1-A: App Engine Flexible
├── app-standard.yaml    # Q1-B / Q2: App Engine Standard (manual scaling + VPC)
├── app-v2.yaml          # Q2: v2 for traffic splitting
├── gcloud-commands.sh   # Complete gcloud CLI playbook (all questions)
└── README.md
```

## Running Locally

```bash
node server.js                              # defaults: PORT=8080 VERSION=v1
APP_VERSION=v2 APP_COLOR=#ec4899 node server.js   # v2 (pink)
```

Visit: http://localhost:8080

## Endpoints

| Method | Path        | Description               |
|--------|-------------|---------------------------|
| GET    | /           | UI page                   |
| GET    | /health     | `{"status":"ok","version":"v1"}` |
| GET    | /api/info   | Full instance metadata JSON |

## Environment Variables

| Variable      | Default    | Description                    |
|---------------|------------|--------------------------------|
| `PORT`        | `8080`     | Listening port                 |
| `APP_VERSION` | `v1`       | Shown in UI and `/api/info`    |
| `APP_COLOR`   | `#6366f1`  | Accent color in UI             |

## GCP Deployments

### Q1-A — App Engine Flex + NEG + Load Balancer
```bash
gcloud builds submit --tag gcr.io/PROJECT_ID/gcp-demo-app .
gcloud app deploy app-flex.yaml
# Then run the LB section in gcloud-commands.sh
```

### Q1-B — App Engine Standard + VPC Connector + Cloud NAT
```bash
# Edit app-standard.yaml → set vpc_access_connector.name
gcloud app deploy app-standard.yaml
```

### Q2 — Manual Scaling + Traffic Split
```bash
gcloud app deploy app-standard.yaml --version=v1 --promote
gcloud app deploy app-v2.yaml       --version=v2 --no-promote
gcloud app services set-traffic default --splits=v1=0.8,v2=0.2 --split-by=random
```

### Q3 — Cloud Run
```bash
gcloud run deploy gcp-demo-app \
  --image=gcr.io/PROJECT_ID/gcp-demo-app \
  --region=us-central1 --allow-unauthenticated
```

### Q4 — Cloud Run Traffic Split
```bash
gcloud run deploy gcp-demo-app --revision-suffix=v2 --no-traffic \
  --set-env-vars="APP_VERSION=v2,APP_COLOR=#ec4899"
gcloud run services update-traffic gcp-demo-app \
  --to-revisions=gcp-demo-app-v1=70,gcp-demo-app-v2=30
```

### Q5 — Internal-only Cloud Run
```bash
gcloud run services update gcp-demo-app --ingress=internal
```

See **gcloud-commands.sh** for the complete step-by-step CLI playbook.
